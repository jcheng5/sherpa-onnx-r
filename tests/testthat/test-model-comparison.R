# Model Comparison Tests
#
# These tests compare different models for accuracy and performance.
# By default, only whisper-tiny runs (fast, suitable for CI).
# Set SHERPA_TEST_ALL_MODELS=true to run full model comparisons.

# Expected transcription for test.wav
EXPECTED_TEXT <- "Posit's mission is to create open source software for data science, scientific research, and technical communication. We do this to enhance the production and consumption of knowledge by everyone, regardless of economic means."

# Helper function to normalize text for comparison (remove extra spaces, punctuation differences)
normalize_text <- function(text) {
  text <- trimws(text)
  text <- tolower(text)
  # Remove punctuation for fuzzy matching
  text <- gsub("[[:punct:]]", "", text)
  text <- gsub("\\s+", " ", text)
  return(text)
}

# Helper function to check if transcription is acceptable
check_transcription <- function(result_text, expected_text, model_name) {
  normalized_result <- normalize_text(result_text)
  normalized_expected <- normalize_text(expected_text)

  # Allow for minor differences (95% similarity)
  similarity <- adist(normalized_result, normalized_expected)
  max_dist <- nchar(normalized_expected) * 0.05  # Allow 5% difference

  expect_true(
    similarity <= max_dist,
    label = sprintf(
      "%s transcription accuracy (distance: %d, max allowed: %.0f)",
      model_name, similarity, max_dist
    )
  )
}

# Check if we should run comprehensive tests
run_all_models <- function() {
  Sys.getenv("SHERPA_TEST_ALL_MODELS", "false") == "true"
}

# Get path to test audio file
get_test_audio <- function() {
  # Try installed location first
  audio_path <- system.file("extdata", "test.wav", package = "sherpa.onnx")

  # Fall back to development location
  if (audio_path == "" || !file.exists(audio_path)) {
    audio_path <- "../../inst/extdata/test.wav"
  }

  if (!file.exists(audio_path)) {
    return(NULL)
  }

  return(audio_path)
}

# Check if test.wav exists
test_audio_exists <- function() {
  !is.null(get_test_audio())
}

# =============================================================================
# DEFAULT TESTS (Always run)
# =============================================================================

test_that("whisper-tiny.en works correctly (default test)", {
  skip_if_not(test_audio_exists(), "test.wav not available")

  audio_path <- get_test_audio()
  rec <- OfflineRecognizer$new(model = "whisper-tiny", verbose = FALSE)
  result <- rec$transcribe(audio_path)

  expect_type(result, "list")
  expect_true("text" %in% names(result))
  expect_type(result$text, "character")
  expect_gt(nchar(result$text), 50)  # Should have substantial text

  # Check transcription quality
  check_transcription(result$text, EXPECTED_TEXT, "whisper-tiny.en")
})

# =============================================================================
# COMPREHENSIVE TESTS (Only run with SHERPA_TEST_ALL_MODELS=true)
# =============================================================================

test_that("All Whisper models produce accurate transcriptions", {
  skip_if_not(run_all_models(), "Set SHERPA_TEST_ALL_MODELS=true to run")
  skip_if_not(test_audio_exists(), "test.wav not available")

  audio_path <- get_test_audio()
  models <- list(
    list(name = "whisper-tiny.en", repo = "whisper-tiny"),
    list(name = "whisper-base.en", repo = "whisper-base"),
    list(name = "whisper-small.en", repo = "csukuangfj/sherpa-onnx-whisper-small.en"),
    list(name = "whisper-medium.en", repo = "csukuangfj/sherpa-onnx-whisper-medium.en"),
    list(name = "whisper-tiny (multilingual)", repo = "csukuangfj/sherpa-onnx-whisper-tiny", language = "en"),
    list(name = "whisper-base (multilingual)", repo = "csukuangfj/sherpa-onnx-whisper-base", language = "en"),
    list(name = "whisper-medium (multilingual)", repo = "csukuangfj/sherpa-onnx-whisper-medium", language = "en"),
    list(name = "whisper-distil-small.en", repo = "csukuangfj/sherpa-onnx-whisper-distil-small.en"),
    list(name = "whisper-distil-medium.en", repo = "csukuangfj/sherpa-onnx-whisper-distil-medium.en")
  )

  for (model_info in models) {
    cat(sprintf("\nTesting %s...\n", model_info$name))

    # Create recognizer
    rec <- if (!is.null(model_info$language)) {
      OfflineRecognizer$new(model = model_info$repo, language = model_info$language, verbose = FALSE)
    } else {
      OfflineRecognizer$new(model = model_info$repo, verbose = FALSE)
    }

    # Transcribe
    result <- rec$transcribe(audio_path)

    # Check result structure
    expect_type(result, "list")
    expect_true("text" %in% names(result))

    # Check transcription quality
    check_transcription(result$text, EXPECTED_TEXT, model_info$name)

    cat(sprintf("✓ %s passed\n", model_info$name))
  }
})

test_that("Whisper models show expected speed progression", {
  skip_if_not(run_all_models(), "Set SHERPA_TEST_ALL_MODELS=true to run")
  skip_if_not(test_audio_exists(), "test.wav not available")

  audio_path <- get_test_audio()
  # Test a subset to verify speed progression
  models <- list(
    list(name = "tiny", repo = "whisper-tiny"),
    list(name = "base", repo = "whisper-base"),
    list(name = "small", repo = "csukuangfj/sherpa-onnx-whisper-small.en")
  )

  times <- numeric(length(models))

  for (i in seq_along(models)) {
    rec <- OfflineRecognizer$new(model = models[[i]]$repo, verbose = FALSE)
    start_time <- Sys.time()
    result <- rec$transcribe(audio_path)
    times[i] <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  }

  # Expect larger models to be slower
  expect_true(times[1] < times[3], "tiny should be faster than small")
  expect_true(times[2] < times[3], "base should be faster than small")

  cat(sprintf("\nSpeed progression: tiny=%.2fs, base=%.2fs, small=%.2fs\n",
              times[1], times[2], times[3]))
})

test_that("All Parakeet models produce accurate transcriptions", {
  skip_if_not(run_all_models(), "Set SHERPA_TEST_ALL_MODELS=true to run")
  skip_if_not(test_audio_exists(), "test.wav not available")

  audio_path <- get_test_audio()
  models <- list(
    list(name = "parakeet-v3-int8", repo = "parakeet-v3"),
    list(name = "parakeet-110m", repo = "csukuangfj/sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000")
  )

  for (model_info in models) {
    cat(sprintf("\nTesting %s...\n", model_info$name))

    rec <- OfflineRecognizer$new(model = model_info$repo, verbose = FALSE)
    result <- rec$transcribe(audio_path)

    expect_type(result, "list")
    expect_true("text" %in% names(result))

    check_transcription(result$text, EXPECTED_TEXT, model_info$name)

    cat(sprintf("✓ %s passed\n", model_info$name))
  }
})

test_that("Parakeet 110m is faster than 600m model", {
  skip_if_not(run_all_models(), "Set SHERPA_TEST_ALL_MODELS=true to run")
  skip_if_not(test_audio_exists(), "test.wav not available")

  audio_path <- get_test_audio()

  # Test 600m model
  rec_600m <- OfflineRecognizer$new(model = "parakeet-v3", verbose = FALSE)
  start_time <- Sys.time()
  result_600m <- rec_600m$transcribe(audio_path)
  time_600m <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  # Test 110m model
  rec_110m <- OfflineRecognizer$new(
    model = "csukuangfj/sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000",
    verbose = FALSE
  )
  start_time <- Sys.time()
  result_110m <- rec_110m$transcribe(audio_path)
  time_110m <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  # 110m should be significantly faster (at least 2x)
  expect_true(time_110m < time_600m / 2,
              sprintf("110m (%.2fs) should be at least 2x faster than 600m (%.2fs)",
                      time_110m, time_600m))

  cat(sprintf("\n110m: %.2fs, 600m: %.2fs (%.1fx speedup)\n",
              time_110m, time_600m, time_600m / time_110m))
})

# =============================================================================
# PERFORMANCE BENCHMARKS (Optional, for development)
# =============================================================================

test_that("Performance benchmark for all models", {
  skip_if_not(Sys.getenv("SHERPA_BENCHMARK", "false") == "true",
              "Set SHERPA_BENCHMARK=true to run benchmarks")
  skip_if_not(test_audio_exists(), "test.wav not available")

  # Run comprehensive benchmarks and save to CSV
  cat("\nRunning comprehensive model benchmarks...\n")
  cat("This will take several minutes and download multiple models.\n\n")

  # This would call the full test scripts
  source("../../test_whisper_models.R", local = TRUE)
  source("../../test_parakeet_models.R", local = TRUE)

  # Check that CSV files were created
  expect_true(file.exists("../../whisper_model_comparison.csv"))
  expect_true(file.exists("../../parakeet_model_comparison.csv"))
})
