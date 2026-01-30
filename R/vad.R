#' Voice Activity Detection
#'
#' @description
#' Detect speech segments in audio using Voice Activity Detection (VAD).
#' Returns timing and audio data for each detected speech segment.
#'
#' @param wav_path Path to WAV file (must be 16kHz, 16-bit, mono)
#' @param threshold Speech detection threshold (0-1). Lower = more sensitive.
#'   Default: 0.5
#' @param min_silence Minimum silence duration (seconds) to split segments.
#'   Default: 0.5
#' @param min_speech Minimum speech duration (seconds) to keep segment.
#'   Default: 0.25
#' @param max_speech Maximum speech duration (seconds) before force split.
#'   Default: 30.0
#' @param model VAD model to use. Default: "silero-vad" (auto-downloaded)
#' @param verbose Logical. Show progress messages. Default: TRUE
#'
#' @return A `sherpa_vad_result` object containing:
#'   - `segments`: List of segment objects, each with:
#'     - `samples`: Numeric vector of audio samples
#'     - `start_time`: Start time in seconds
#'     - `duration`: Duration in seconds
#'   - `num_segments`: Number of detected segments
#'   - `sample_rate`: Sample rate of the audio
#'
#' @details
#' This function uses the Silero VAD model to detect speech in audio.
#' It's useful for:
#' - Finding speech regions in long recordings
#' - Pre-processing audio before transcription
#' - Audio analysis and editing
#'
#' The returned segments contain the actual audio samples, which can be
#' used for further processing or saved to separate files.
#'
#' @examples
#' \dontrun{
#' # Detect speech in audio
#' result <- vad("recording.wav")
#' print(result)
#'
#' # Access individual segments
#' for (i in seq_along(result$segments)) {
#'   seg <- result$segments[[i]]
#'   cat(sprintf("Segment %d: %.2f - %.2f sec\n",
#'               i, seg$start_time, seg$start_time + seg$duration))
#' }
#'
#' # Use more sensitive detection
#' result <- vad("quiet_recording.wav", threshold = 0.3)
#' }
#'
#' @export
vad <- function(wav_path,
                threshold = 0.5,
                min_silence = 0.5,
                min_speech = 0.25,
                max_speech = 30.0,
                model = "silero-vad",
                verbose = TRUE) {
  # Expand path

wav_path <- path.expand(wav_path)

  if (!file.exists(wav_path)) {
    stop("WAV file not found: ", wav_path)
  }

  # Validate parameters
  if (threshold < 0 || threshold > 1) {
    stop("threshold must be between 0 and 1")
  }
  if (min_silence < 0) {
    stop("min_silence must be non-negative")
  }
  if (min_speech < 0) {
    stop("min_speech must be non-negative")
  }
  if (max_speech <= 0) {
    stop("max_speech must be positive")
  }

  # Load audio
  wav_data <- read_wav_(wav_path)

  # Download VAD model if needed
  vad_model_path <- download_vad_model(model, verbose = verbose)

  # Run VAD
  vad_result <- extract_vad_segments_(
    vad_model_path,
    wav_data$samples,
    wav_data$sample_rate,
    threshold,
    min_silence,
    min_speech,
    max_speech,
    512L,  # window_size for Silero VAD
    verbose
  )

  # Create result object
  new_sherpa_vad_result(
    segments = vad_result$segments,
    num_segments = vad_result$num_segments,
    sample_rate = wav_data$sample_rate,
    source_file = wav_path
  )
}

#' Create a sherpa_vad_result object
#'
#' @param segments List of segment objects from extract_vad_segments_()
#' @param num_segments Number of segments
#' @param sample_rate Audio sample rate
#' @param source_file Original WAV file path
#'
#' @return A sherpa_vad_result object
#' @keywords internal
new_sherpa_vad_result <- function(segments, num_segments, sample_rate, source_file) {
  structure(
    list(
      segments = segments,
      num_segments = num_segments,
      sample_rate = sample_rate
    ),
    class = c("sherpa_vad_result", "list"),
    source_file = source_file
  )
}

#' Print method for sherpa_vad_result
#'
#' @param x A sherpa_vad_result object
#' @param ... Additional arguments (ignored)
#'
#' @return The object invisibly
#' @export
print.sherpa_vad_result <- function(x, ...) {
  cat(sprintf("[VAD: %d segment%s]\n\n",
              x$num_segments,
              if (x$num_segments == 1) "" else "s"))

  if (x$num_segments == 0) {
    cat("No speech detected.\n")
  } else {
    # Show segment summary
    for (i in seq_along(x$segments)) {
      seg <- x$segments[[i]]
      end_time <- seg$start_time + seg$duration
      cat(sprintf("  [%d] %.2f - %.2f sec (%.2f sec)\n",
                  i, seg$start_time, end_time, seg$duration))
    }
  }

  invisible(x)
}

#' Summary method for sherpa_vad_result
#'
#' @param object A sherpa_vad_result object
#' @param ... Additional arguments (ignored)
#'
#' @return The object invisibly
#' @export
summary.sherpa_vad_result <- function(object, ...) {
  cat("Voice Activity Detection Result\n")
  cat("================================\n\n")

  # Source file
  source_file <- attr(object, "source_file")
  if (!is.null(source_file)) {
    cat(sprintf("Source: %s\n", basename(source_file)))
  }
  cat(sprintf("Sample rate: %d Hz\n", object$sample_rate))
  cat(sprintf("Segments detected: %d\n\n", object$num_segments))

  if (object$num_segments > 0) {
    # Calculate statistics
    durations <- vapply(object$segments, function(s) s$duration, numeric(1))
    starts <- vapply(object$segments, function(s) s$start_time, numeric(1))

    total_speech <- sum(durations)
    audio_end <- max(starts + durations)

    cat("Timing Statistics:\n")
    cat(sprintf("  Total speech: %.2f sec\n", total_speech))
    cat(sprintf("  Audio span: 0.00 - %.2f sec\n", audio_end))
    cat(sprintf("  Speech ratio: %.1f%%\n", 100 * total_speech / audio_end))
    cat("\n")

    cat("Segment Details:\n")
    cat(sprintf("  %-6s  %-12s  %-12s  %-10s  %-10s\n",
                "Seg", "Start", "End", "Duration", "Samples"))
    cat(sprintf("  %-6s  %-12s  %-12s  %-10s  %-10s\n",
                "---", "-----", "---", "--------", "-------"))
    for (i in seq_along(object$segments)) {
      seg <- object$segments[[i]]
      cat(sprintf("  %-6d  %-12.2f  %-12.2f  %-10.2f  %-10d\n",
                  i,
                  seg$start_time,
                  seg$start_time + seg$duration,
                  seg$duration,
                  length(seg$samples)))
    }
  }

  invisible(object)
}

#' Extract audio samples from a VAD segment
#'
#' @param vad_result A sherpa_vad_result object
#' @param segment_index Index of segment to extract (1-based)
#'
#' @return Numeric vector of audio samples
#'
#' @examples
#' \dontrun{
#' result <- vad("recording.wav")
#' # Get samples from first segment
#' samples <- vad_segment_samples(result, 1)
#' }
#'
#' @export
vad_segment_samples <- function(vad_result, segment_index) {
  if (!inherits(vad_result, "sherpa_vad_result")) {
    stop("vad_result must be a sherpa_vad_result object")
  }
  if (segment_index < 1 || segment_index > vad_result$num_segments) {
    stop(sprintf("segment_index must be between 1 and %d", vad_result$num_segments))
  }
  vad_result$segments[[segment_index]]$samples
}

#' Convert VAD result to a data frame
#'
#' @param x A sherpa_vad_result object
#' @param row.names NULL or character vector of row names (ignored)
#' @param optional Logical, if TRUE, column names are optional (ignored)
#' @param ... Additional arguments (ignored)
#'
#' @return A data frame with columns: segment, start_time, end_time, duration, num_samples
#'
#' @examples
#' \dontrun{
#' result <- vad("recording.wav")
#' df <- as.data.frame(result)
#' print(df)
#' }
#'
#' @export
as.data.frame.sherpa_vad_result <- function(x, row.names = NULL, optional = FALSE, ...) {
  if (x$num_segments == 0) {
    return(data.frame(
      segment = integer(0),
      start_time = numeric(0),
      end_time = numeric(0),
      duration = numeric(0),
      num_samples = integer(0)
    ))
  }

  data.frame(
    segment = seq_len(x$num_segments),
    start_time = vapply(x$segments, function(s) s$start_time, numeric(1)),
    end_time = vapply(x$segments, function(s) s$start_time + s$duration, numeric(1)),
    duration = vapply(x$segments, function(s) s$duration, numeric(1)),
    num_samples = vapply(x$segments, function(s) length(s$samples), integer(1))
  )
}
