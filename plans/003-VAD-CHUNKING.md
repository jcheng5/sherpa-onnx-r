# Implementation Plan: VAD-Based Audio Chunking

## Overview
Replace the current time-based chunking implementation with VAD (Voice Activity Detection) based chunking. This provides superior transcription quality by splitting audio at natural pauses rather than arbitrary time boundaries.

## Why VAD is Better

| Aspect | Time-based chunks (current) | VAD-based (proposed) |
|--------|---------------------------|---------------------|
| Boundary quality | Arbitrary, may cut mid-word | Natural pauses |
| Overlap needed | Yes (15s) | No |
| Merging logic | Complex, bug-prone | Simple concatenation |
| Model requirements | Needs timestamps (parakeet/sense-voice only) | Any model |
| Code complexity | High (overlap handling) | Medium |
| Results quality | Lower (broken utterances) | Higher (complete utterances) |
| Bugs | Current overlap logic discards ALL tokens in overlap region | None |

## Architecture

```
User calls: rec$transcribe("long.wav", use_vad = TRUE)
     ↓
R Layer (recognizer.R)
  1. Download VAD model if needed
  2. Load entire audio file
  3. Call C++ VAD wrapper
     ↓
C++ Layer (vad.cpp - NEW FILE)
  1. Create VAD instance
  2. Feed audio in windows
  3. Extract speech segments
  4. For each segment:
     - Transcribe using existing recognizer
     - Track timing info
  5. Concatenate results
     ↓
Return sherpa_transcription with timing
```

## Implementation Steps

### Step 1: Add VAD Model Management (R/model.R)

Add VAD model to shorthand list:

```r
SHORTHAND_MODELS <- list(
  # ... existing models ...
  
  # VAD models
  "silero-vad" = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"
)
```

Add VAD-specific download function:

```r
#' Download VAD model
#'
#' @param vad_model VAD model name or URL (default: "silero-vad")
#' @param verbose Whether to print progress
#' @return Path to downloaded VAD model
#' @noRd
download_vad_model <- function(vad_model = "silero-vad", verbose = TRUE) {
  cache_dir <- get_cache_dir()
  vad_cache <- file.path(cache_dir, "vad")
  
  if (!dir.exists(vad_cache)) {
    dir.create(vad_cache, recursive = TRUE)
  }
  
  # Handle shorthand or URL
  if (vad_model == "silero-vad") {
    url <- "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"
    local_path <- file.path(vad_cache, "silero_vad.onnx")
  } else if (grepl("^https?://", vad_model)) {
    url <- vad_model
    local_path <- file.path(vad_cache, basename(vad_model))
  } else {
    # Assume it's a local path
    if (file.exists(vad_model)) {
      return(normalizePath(vad_model))
    }
    stop("VAD model not found: ", vad_model)
  }
  
  # Check if already cached
  if (file.exists(local_path)) {
    if (verbose) message("Using cached VAD model: ", local_path)
    return(local_path)
  }
  
  if (verbose) message("Downloading VAD model from: ", url)
  
  # Download
  tryCatch({
    download.file(url, local_path, mode = "wb", quiet = !verbose)
    if (verbose) message("VAD model downloaded to: ", local_path)
    return(local_path)
  }, error = function(e) {
    stop("Failed to download VAD model: ", e$message)
  })
}
```

### Step 2: Create C++ VAD Wrapper (src/vad.cpp - NEW FILE)

```cpp
#include <cpp11.hpp>
#include "sherpa-onnx/c-api/c-api.h"

using namespace cpp11;

// VAD configuration helper
SherpaOnnxVadModelConfig create_vad_config(
    const char* model_path,
    float threshold,
    float min_silence_duration,
    float min_speech_duration,
    float max_speech_duration,
    int32_t window_size,
    int32_t sample_rate,
    int32_t num_threads,
    bool debug) {
  
  SherpaOnnxVadModelConfig config;
  memset(&config, 0, sizeof(config));
  
  // Configure Silero VAD
  config.silero_vad.model = model_path;
  config.silero_vad.threshold = threshold;
  config.silero_vad.min_silence_duration = min_silence_duration;
  config.silero_vad.min_speech_duration = min_speech_duration;
  config.silero_vad.max_speech_duration = max_speech_duration;
  config.silero_vad.window_size = window_size;
  
  config.sample_rate = sample_rate;
  config.num_threads = num_threads;
  config.debug = debug ? 1 : 0;
  
  return config;
}

// Transcribe with VAD segmentation
// This is the main function that R will call
[[cpp11::register]]
list transcribe_with_vad_(
    SEXP recognizer_xptr,
    std::string vad_model_path,
    doubles samples,
    int sample_rate,
    double vad_threshold,
    double vad_min_silence,
    double vad_min_speech,
    double vad_max_speech,
    int vad_window_size,
    bool verbose) {
  
  // Get recognizer from external pointer
  external_pointer<const SherpaOnnxOfflineRecognizer> recognizer(recognizer_xptr);
  
  if (recognizer.get() == nullptr) {
    stop("Invalid recognizer pointer");
  }
  
  if (samples.size() == 0) {
    stop("Empty audio samples");
  }
  
  // Convert R doubles to float array
  std::vector<float> samples_vec(samples.size());
  for (size_t i = 0; i < samples.size(); ++i) {
    samples_vec[i] = static_cast<float>(samples[i]);
  }
  
  // Create VAD configuration
  SherpaOnnxVadModelConfig vad_config = create_vad_config(
    vad_model_path.c_str(),
    vad_threshold,
    vad_min_silence,
    vad_min_speech,
    vad_max_speech,
    vad_window_size,
    sample_rate,
    1,  // num_threads
    verbose
  );
  
  // Create VAD instance (buffer size = 30 seconds)
  const SherpaOnnxVoiceActivityDetector *vad =
      SherpaOnnxCreateVoiceActivityDetector(&vad_config, 30.0f);
  
  if (vad == nullptr) {
    stop("Failed to create VAD instance. Check model path: %s", vad_model_path.c_str());
  }
  
  // Process audio through VAD
  int32_t i = 0;
  int is_eof = 0;
  
  // Storage for all segments
  writable::list all_segments;
  writable::doubles all_start_times;
  writable::doubles all_durations;
  writable::strings all_texts;
  
  int segment_count = 0;
  
  while (!is_eof) {
    // Feed audio to VAD in windows
    if (i + vad_window_size < samples_vec.size()) {
      SherpaOnnxVoiceActivityDetectorAcceptWaveform(
          vad, samples_vec.data() + i, vad_window_size);
    } else {
      // Last chunk - flush VAD
      SherpaOnnxVoiceActivityDetectorFlush(vad);
      is_eof = 1;
    }
    
    // Process all available speech segments
    while (!SherpaOnnxVoiceActivityDetectorEmpty(vad)) {
      const SherpaOnnxSpeechSegment *segment =
          SherpaOnnxVoiceActivityDetectorFront(vad);
      
      segment_count++;
      
      if (verbose) {
        float start_sec = segment->start / (float)sample_rate;
        float duration_sec = segment->n / (float)sample_rate;
        Rprintf("Processing segment %d: %.2f - %.2f sec (%.2f sec)\n",
                segment_count, start_sec, start_sec + duration_sec, duration_sec);
      }
      
      // Create stream and transcribe this segment
      const SherpaOnnxOfflineStream *stream =
          SherpaOnnxCreateOfflineStream(recognizer.get());
      
      SherpaOnnxAcceptWaveformOffline(
          stream, sample_rate, segment->samples, segment->n);
      
      SherpaOnnxDecodeOfflineStream(recognizer.get(), stream);
      
      const SherpaOnnxOfflineRecognizerResult *result =
          SherpaOnnxGetOfflineStreamResult(stream);
      
      // Store segment info
      float start_time = segment->start / (float)sample_rate;
      float duration = segment->n / (float)sample_rate;
      
      all_start_times.push_back(start_time);
      all_durations.push_back(duration);
      all_texts.push_back(std::string(result->text));
      
      // Cleanup segment
      SherpaOnnxDestroyOfflineRecognizerResult(result);
      SherpaOnnxDestroyOfflineStream(stream);
      SherpaOnnxDestroySpeechSegment(segment);
      SherpaOnnxVoiceActivityDetectorPop(vad);
    }
    
    i += vad_window_size;
  }
  
  // Cleanup VAD
  SherpaOnnxDestroyVoiceActivityDetector(vad);
  
  // Build combined result
  std::string full_text;
  for (size_t i = 0; i < all_texts.size(); ++i) {
    if (i > 0 && all_texts[i].length() > 0) {
      full_text += " ";  // Add space between segments
    }
    full_text += all_texts[i];
  }
  
  writable::list out;
  out.push_back({"text"_nm = full_text});
  out.push_back({"segments"_nm = all_texts});
  out.push_back({"segment_starts"_nm = all_start_times});
  out.push_back({"segment_durations"_nm = all_durations});
  out.push_back({"num_segments"_nm = segment_count});
  
  return out;
}
```

### Step 3: Update R/cpp11.R (Auto-generated)

After creating `src/vad.cpp`, run:

```r
cpp11::cpp_register()
```

This will add the binding:

```r
transcribe_with_vad_ <- function(recognizer_xptr, vad_model_path, samples, 
                                  sample_rate, vad_threshold, vad_min_silence,
                                  vad_min_speech, vad_max_speech, vad_window_size,
                                  verbose) {
  .Call(`_sherpa_onnx_transcribe_with_vad_`, recognizer_xptr, vad_model_path, 
        samples, sample_rate, vad_threshold, vad_min_silence, vad_min_speech,
        vad_max_speech, vad_window_size, verbose)
}
```

### Step 4: Update R/recognizer.R

Replace the `transcribe_chunked()` method with VAD version:

```r
# Private method for VAD-based transcription
transcribe_with_vad = function(wav_path, vad_config) {
  # Load audio
  wav_data <- read_wav_(wav_path)
  samples <- wav_data$samples
  sample_rate <- wav_data$sample_rate
  
  # Ensure VAD model is available
  vad_model_path <- download_vad_model(
    vad_config$model, 
    verbose = vad_config$verbose
  )
  
  # Call C++ VAD transcription
  result <- transcribe_with_vad_(
    private$recognizer_ptr,
    vad_model_path,
    samples,
    sample_rate,
    vad_config$threshold,
    vad_config$min_silence,
    vad_config$min_speech,
    vad_config$max_speech,
    vad_config$window_size,
    vad_config$verbose
  )
  
  # Add metadata
  result$vad_config <- vad_config
  
  # Create transcription object with segment info
  new_sherpa_transcription(result, private$model_info_cache)
}
```

Update the public `transcribe()` method:

```r
#' @description
#' Transcribe a WAV file
#'
#' @param wav_path Path to WAV file (must be 16kHz, 16-bit, mono)
#' @param use_vad Logical. If TRUE, uses Voice Activity Detection to split
#'   long audio files at natural pauses. Recommended for files longer than
#'   30 seconds. Default: FALSE (transcribe entire file at once).
#' @param vad_threshold Speech detection threshold (0-1). Lower = more sensitive.
#'   Default: 0.5
#' @param vad_min_silence Minimum silence duration (seconds) to split segments.
#'   Default: 0.5
#' @param vad_min_speech Minimum speech duration (seconds) to keep segment.
#'   Default: 0.25
#' @param vad_max_speech Maximum speech duration (seconds) before force split.
#'   Default: 30.0. Useful to prevent memory issues with very long speech.
#' @param vad_model VAD model to use. Default: "silero-vad" (auto-downloaded)
#' @param verbose Logical. Show progress messages. Default: TRUE
#'
#' @return A sherpa_transcription object containing:
#'   - text: Full transcribed text
#'   - segments: Character vector of segment texts (if VAD used)
#'   - segment_starts: Start times of segments in seconds (if VAD used)
#'   - segment_durations: Duration of segments in seconds (if VAD used)
#'
#' @examples
#' \dontrun{
#' # Simple transcription
#' rec <- OfflineRecognizer$new(model = "whisper-tiny")
#' result <- rec$transcribe("short_audio.wav")
#'
#' # Long audio with VAD
#' result <- rec$transcribe("podcast.wav", use_vad = TRUE)
#' print(result)  # Shows full text
#' result$segments  # Individual speech segments
#' result$segment_starts  # Timing of each segment
#' }
transcribe = function(wav_path, 
                     use_vad = FALSE,
                     vad_threshold = 0.5,
                     vad_min_silence = 0.5,
                     vad_min_speech = 0.25,
                     vad_max_speech = 30.0,
                     vad_model = "silero-vad",
                     verbose = TRUE) {
  # Expand tilde and other path shortcuts
  wav_path <- path.expand(wav_path)

  if (!file.exists(wav_path)) {
    stop("WAV file not found: ", wav_path)
  }

  if (is.null(private$recognizer_ptr)) {
    stop("Recognizer not initialized")
  }

  # Simple transcription (no VAD)
  if (!use_vad) {
    result <- transcribe_wav_(private$recognizer_ptr, wav_path)
    return(new_sherpa_transcription(result, private$model_info_cache))
  }

  # VAD-based transcription
  vad_config <- list(
    model = vad_model,
    threshold = vad_threshold,
    min_silence = vad_min_silence,
    min_speech = vad_min_speech,
    max_speech = vad_max_speech,
    window_size = 512,  # Silero VAD window size
    verbose = verbose
  )
  
  private$transcribe_with_vad(wav_path, vad_config)
}
```

### Step 5: Update R/transcription.R

Enhance the S3 class to handle VAD segment info:

```r
#' Print method for sherpa_transcription
#' @export
print.sherpa_transcription <- function(x, ...) {
  # Get model name for display
  model_info <- attr(x, "model_info")
  model_name <- model_info$shorthand %||% 
                basename(model_info$path) %||% 
                "unknown"
  
  # Build metadata line
  metadata_parts <- character()
  
  # Token count (if available)
  if (!is.null(x$tokens) && length(x$tokens) > 0) {
    metadata_parts <- c(metadata_parts, sprintf("%d tokens", length(x$tokens)))
  }
  
  # Segment count (if VAD was used)
  if (!is.null(x$num_segments) && x$num_segments > 0) {
    metadata_parts <- c(metadata_parts, sprintf("%d segments", x$num_segments))
  }
  
  # Model name
  metadata_parts <- c(metadata_parts, model_name)
  
  # Print metadata line
  cat(sprintf("[%s]\n", paste(metadata_parts, collapse = " | ")))
  cat("\n")
  
  # Print text
  cat(x$text)
  cat("\n")
  
  invisible(x)
}

#' Summary method for sherpa_transcription
#' @export
summary.sherpa_transcription <- function(object, ...) {
  cat("Sherpa-ONNX Transcription\n")
  cat("=========================\n\n")
  
  model_info <- attr(object, "model_info")
  if (!is.null(model_info)) {
    cat("Model:", model_info$shorthand %||% basename(model_info$path), "\n")
    if (!is.null(model_info$repo)) {
      cat("Repo:", model_info$repo, "\n")
    }
  }
  cat("\n")
  
  # Text statistics
  cat("Text Statistics:\n")
  cat("  Characters:", nchar(object$text), "\n")
  cat("  Words:", length(strsplit(object$text, "\\s+")[[1]]), "\n")
  if (!is.null(object$tokens)) {
    cat("  Tokens:", length(object$tokens), "\n")
  }
  cat("\n")
  
  # VAD segment info (if available)
  if (!is.null(object$num_segments) && object$num_segments > 0) {
    cat("VAD Segmentation:\n")
    cat("  Segments:", object$num_segments, "\n")
    if (!is.null(object$segment_starts) && length(object$segment_starts) > 0) {
      total_duration <- max(object$segment_starts + object$segment_durations)
      speech_duration <- sum(object$segment_durations)
      cat("  Total duration:", sprintf("%.1f sec", total_duration), "\n")
      cat("  Speech duration:", sprintf("%.1f sec", speech_duration), "\n")
      cat("  Speech ratio:", sprintf("%.1f%%", 100 * speech_duration / total_duration), "\n")
    }
    cat("\n")
  }
  
  # Available fields
  cat("Available Fields:\n")
  for (name in names(object)) {
    value <- object[[name]]
    if (is.null(value)) {
      cat(sprintf("  %-20s: NULL\n", name))
    } else if (is.character(value)) {
      if (length(value) == 1) {
        preview <- if (nchar(value) > 50) paste0(substr(value, 1, 47), "...") else value
        cat(sprintf("  %-20s: chr \"%s\"\n", name, preview))
      } else {
        cat(sprintf("  %-20s: chr[%d]\n", name, length(value)))
      }
    } else if (is.numeric(value)) {
      cat(sprintf("  %-20s: num[%d]\n", name, length(value)))
    } else {
      cat(sprintf("  %-20s: %s\n", name, class(value)[1]))
    }
  }
  
  invisible(object)
}
```

### Step 6: Update DESCRIPTION

Add note about VAD support:

```
Description: R interface to sherpa-onnx for automatic speech recognition (ASR).
    Supports multiple model architectures including Whisper, Parakeet, and SenseVoice.
    Includes Voice Activity Detection (VAD) for processing long audio files.
    Models are automatically downloaded from HuggingFace Hub.
```

### Step 7: Create Tests (tests/testthat/test-vad.R - NEW FILE)

```r
test_that("VAD transcription works", {
  skip_if_not(file.exists(system.file("extdata", "test.wav", package = "sherpa.onnx")),
              "test.wav not available")
  
  rec <- OfflineRecognizer$new(model = "whisper-tiny")
  
  # Test VAD transcription
  result <- rec$transcribe(
    system.file("extdata", "test.wav", package = "sherpa.onnx"),
    use_vad = TRUE,
    verbose = FALSE
  )
  
  # Check structure
  expect_s3_class(result, "sherpa_transcription")
  expect_type(result$text, "character")
  expect_true(nchar(result$text) > 0)
  
  # Check VAD-specific fields
  expect_true("num_segments" %in% names(result))
  expect_true("segments" %in% names(result))
  expect_true("segment_starts" %in% names(result))
  expect_true("segment_durations" %in% names(result))
  
  # Segments should be non-empty
  expect_true(result$num_segments > 0)
  expect_equal(length(result$segments), result$num_segments)
  expect_equal(length(result$segment_starts), result$num_segments)
  expect_equal(length(result$segment_durations), result$num_segments)
})

test_that("VAD model auto-downloads", {
  # This should trigger download if not cached
  vad_path <- download_vad_model("silero-vad", verbose = FALSE)
  
  expect_true(file.exists(vad_path))
  expect_match(vad_path, "silero_vad.onnx$")
})

test_that("VAD parameters are validated", {
  rec <- OfflineRecognizer$new(model = "whisper-tiny")
  
  # Invalid threshold
  expect_error(
    rec$transcribe("test.wav", use_vad = TRUE, vad_threshold = 1.5),
    "threshold"
  )
  
  # Negative durations
  expect_error(
    rec$transcribe("test.wav", use_vad = TRUE, vad_min_silence = -1),
    "silence"
  )
})
```

### Step 8: Update Documentation

Add a vignette: `vignettes/long-audio.Rmd`

```markdown
---
title: "Processing Long Audio Files with VAD"
output: rmarkdown::html_vignette
vignette: >
  %\VignetteIndexEntry{Processing Long Audio Files with VAD}
  %\VignetteEngine{knitr::rmarkdown}
  %\VignetteEncoding{UTF-8}
---

## Why Use VAD?

Voice Activity Detection (VAD) automatically splits long audio files at natural
pauses, improving transcription quality and reducing memory usage.

## Basic Usage

```r
library(sherpa.onnx)

rec <- OfflineRecognizer$new(model = "whisper-tiny")

# Transcribe a long podcast
result <- rec$transcribe("podcast.wav", use_vad = TRUE)

# Full text
print(result$text)

# Individual segments with timing
for (i in seq_along(result$segments)) {
  cat(sprintf("[%.1f - %.1f]: %s\n",
              result$segment_starts[i],
              result$segment_starts[i] + result$segment_durations[i],
              result$segments[i]))
}
```

## Tuning VAD Parameters

- `vad_threshold`: Lower = more sensitive (default: 0.5)
- `vad_min_silence`: Minimum silence to split (default: 0.5 sec)
- `vad_max_speech`: Force split after this duration (default: 30 sec)

```r
# More aggressive splitting (for faster speakers)
result <- rec$transcribe("fast_speech.wav",
                        use_vad = TRUE,
                        vad_min_silence = 0.3)

# Higher quality (less aggressive splitting)
result <- rec$transcribe("careful_speech.wav",
                        use_vad = TRUE,
                        vad_threshold = 0.6,
                        vad_min_silence = 0.8)
```
```

## Migration Guide: Old Time-Based Chunking → VAD

### What to Remove

1. **Delete**: The `transcribe_chunked()` private method (lines 26-147 in R/recognizer.R)
2. **Delete**: The `transcribe_samples_()` C++ function (src/recognizer.cpp, src/cpp11.cpp)
3. **Delete**: Parameters `chunk_duration` and `overlap_duration` from `transcribe()`

### What to Keep

- The `read_wav_()` C++ function (still useful for R-side access to audio)
- All existing simple transcription code
- S3 class infrastructure in R/transcription.R

## Testing Checklist

- [ ] Create `src/vad.cpp` with VAD wrapper
- [ ] Run `cpp11::cpp_register()` to update bindings
- [ ] Add `download_vad_model()` to R/model.R
- [ ] Add `transcribe_with_vad()` private method to R/recognizer.R
- [ ] Update `transcribe()` public method with VAD parameters
- [ ] Update `print.sherpa_transcription()` to show segment info
- [ ] Update `summary.sherpa_transcription()` to show VAD stats
- [ ] Create `tests/testthat/test-vad.R`
- [ ] Test with short audio (< 10 seconds)
- [ ] Test with long audio (> 60 seconds)
- [ ] Test with different models (Whisper, Parakeet, SenseVoice)
- [ ] Verify VAD model auto-downloads
- [ ] Update DESCRIPTION and NEWS.md
- [ ] Create vignette

## Expected Benefits

1. **Better Quality**: Segments at natural pauses, not mid-sentence
2. **Universal**: Works with ANY model (not just timestamp-supporting ones)
3. **Simpler**: No complex overlap/merge logic
4. **Faster**: No duplicate processing of overlap regions
5. **Bug-Free**: Eliminates the current overlap bug that drops tokens

## File Summary

| File | Action | Description |
|------|--------|-------------|
| `src/vad.cpp` | CREATE | C++ VAD wrapper with `transcribe_with_vad_()` |
| `R/cpp11.R` | AUTO-UPDATE | Run `cpp11::cpp_register()` |
| `R/model.R` | MODIFY | Add `download_vad_model()` function |
| `R/recognizer.R` | MODIFY | Replace chunking with VAD, update `transcribe()` |
| `R/transcription.R` | MODIFY | Update print/summary for segments |
| `tests/testthat/test-vad.R` | CREATE | VAD-specific tests |
| `vignettes/long-audio.Rmd` | CREATE | User documentation |
| `src/recognizer.cpp` | MODIFY | Remove `transcribe_samples_()` |
| `plans/002-S3-CLASS.md` | DONE | Already implemented |
| `plans/003-VAD-CHUNKING.md` | THIS FILE | Implementation guide |

## Estimated Effort

- C++ VAD wrapper: 1-2 hours
- R integration: 1 hour
- Testing: 1 hour
- Documentation: 30 minutes
- **Total: 3-4 hours**

Much simpler than debugging the time-based overlap logic!
