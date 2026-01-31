# Helper function to get test audio path
get_test_audio <- function() {
  # Try installed location first
  audio_path <- system.file("extdata", "test.wav", package = "sherpa.onnx")
  # Fall back to development location
  if (audio_path == "" || !file.exists(audio_path)) {
    audio_path <- "../../inst/extdata/test.wav"
  }
  # Another fallback for different test contexts
  if (!file.exists(audio_path)) {
    audio_path <- "../test.wav"
  }
  return(audio_path)
}

test_that("OfflineRecognizer class exists", {
  expect_true(exists("OfflineRecognizer"))
  expect_s3_class(OfflineRecognizer, "R6ClassGenerator")
})

test_that("OfflineRecognizer fails gracefully with invalid model", {
  expect_error(
    OfflineRecognizer$new(model = "nonexistent-model-xyz"),
    "Unknown model shorthand"
  )
})

# Skip actual recognizer tests if we don't have a test model
# These tests would run in CI/CD with proper test fixtures
test_that("OfflineRecognizer can be created with local model", {
  skip_if_not(dir.exists("test-model"), "Test model not available")

  rec <- OfflineRecognizer$new(model = "test-model")
  expect_s3_class(rec, "OfflineRecognizer")
  expect_false(is.null(rec$model_info()))
})

test_that("OfflineRecognizer transcribe fails with missing file", {
  skip_if_not(dir.exists("test-model"), "Test model not available")

  rec <- OfflineRecognizer$new(model = "test-model")
  expect_error(
    rec$transcribe("nonexistent.wav"),
    "WAV file not found"
  )
})

test_that("OfflineRecognizer transcribe works with test audio", {
  skip_if_not(dir.exists("test-model"), "Test model not available")
  skip_if_not(file.exists("test-audio.wav"), "Test audio not available")

  rec <- OfflineRecognizer$new(model = "test-model")
  result <- rec$transcribe("test-audio.wav")

  expect_type(result, "list")
  expect_true("text" %in% names(result))
  expect_type(result$text, "character")
})

# S3 Class Tests
test_that("transcribe returns sherpa_transcription S3 class", {
  skip_if_not(file.exists(get_test_audio()), "Test audio not available")

  rec <- OfflineRecognizer$new(model = "whisper-tiny")
  result <- rec$transcribe(get_test_audio())

  # Check S3 class
  expect_s3_class(result, "sherpa_transcription")
  expect_s3_class(result, "list")  # Should inherit from list

  # Check backward compatibility - list access still works
  expect_true("text" %in% names(result))
  expect_type(result$text, "character")
  expect_type(result$tokens, "character")

  # Check S3 methods
  expect_type(as.character(result), "character")
  expect_equal(as.character(result), result$text)

  # Check print method works (shouldn't error)
  expect_output(print(result), "tokens")
  expect_output(print(result), "whisper-tiny")

  # Check summary method works
  expect_output(summary(result), "Sherpa-ONNX Transcription")
  expect_output(summary(result), "Text Statistics")
})

test_that("sherpa_transcription print method handles edge cases", {
  skip_if_not(file.exists(get_test_audio()), "Test audio not available")

  rec <- OfflineRecognizer$new(model = "whisper-tiny")
  result <- rec$transcribe(get_test_audio())

  # Test that print returns invisibly
  return_value <- print(result)
  expect_identical(return_value, result)

  # Test print output format
  output <- capture.output(print(result))
  expect_match(output[1], "\\[\\d+ tokens \\| .+\\]")  # Metadata line
  expect_equal(output[2], "")  # Blank line
  expect_true(length(output) >= 3)  # Has text content
})

test_that("as.character.sherpa_transcription extracts text", {
  skip_if_not(file.exists(get_test_audio()), "Test audio not available")

  rec <- OfflineRecognizer$new(model = "whisper-tiny")
  result <- rec$transcribe(get_test_audio())

  text <- as.character(result)
  expect_identical(text, result$text)
  expect_type(text, "character")
  expect_true(nchar(text) > 0)
})

test_that("summary.sherpa_transcription shows detailed info", {
  skip_if_not(file.exists(get_test_audio()), "Test audio not available")

  rec <- OfflineRecognizer$new(model = "whisper-tiny")
  result <- rec$transcribe(get_test_audio())

  output <- capture.output(summary(result))
  output_text <- paste(output, collapse = "\n")

  # Check for expected sections
  expect_match(output_text, "Sherpa-ONNX Transcription")
  expect_match(output_text, "Model:")
  expect_match(output_text, "Text Statistics:")
  expect_match(output_text, "Characters:")
  expect_match(output_text, "Words:")
  expect_match(output_text, "Tokens:")
  expect_match(output_text, "Available Fields:")
})

test_that("OfflineRecognizer transcribe_batch works", {
  skip_if_not(dir.exists("test-model"), "Test model not available")
  skip_if_not(file.exists("test-audio.wav"), "Test audio not available")

  rec <- OfflineRecognizer$new(model = "test-model")
  results <- rec$transcribe_batch(c("test-audio.wav", "test-audio.wav"))

  # Should return a tibble
  expect_s3_class(results, "tbl_df")
  expect_equal(nrow(results), 2)

  # Check column names
  expect_true("file" %in% names(results))
  expect_true("text" %in% names(results))
  expect_true("tokens" %in% names(results))
  expect_true("timestamps" %in% names(results))
  expect_true("durations" %in% names(results))
  expect_true("language" %in% names(results))
  expect_true("emotion" %in% names(results))
  expect_true("event" %in% names(results))
  expect_true("json" %in% names(results))

  # Check column types
  expect_type(results$file, "character")
  expect_type(results$text, "character")
  expect_type(results$tokens, "list")
  expect_type(results$timestamps, "list")
  expect_type(results$durations, "list")
})

test_that("OfflineRecognizer transcribe_batch returns empty tibble for empty input", {
  skip_if_not(dir.exists("test-model"), "Test model not available")

  rec <- OfflineRecognizer$new(model = "test-model")
  results <- rec$transcribe_batch(character(0))

  # Should return empty tibble with correct structure
  expect_s3_class(results, "tbl_df")
  expect_equal(nrow(results), 0)
  expect_equal(ncol(results), 9)
  expect_true("file" %in% names(results))
  expect_true("text" %in% names(results))
})

test_that("OfflineRecognizer model_info returns information", {
  skip_if_not(dir.exists("test-model"), "Test model not available")

  rec <- OfflineRecognizer$new(model = "test-model")
  info <- rec$model_info()

  expect_type(info, "list")
  expect_true("path" %in% names(info))
  expect_true("model_type" %in% names(info))
})

test_that("read_wav works with valid WAV file", {
  test_audio <- get_test_audio()
  skip_if_not(file.exists(test_audio), "Test WAV not available")

  result <- read_wav(test_audio)

  expect_type(result, "list")
  expect_true("samples" %in% names(result))
  expect_true("sample_rate" %in% names(result))
  expect_true("num_samples" %in% names(result))
  expect_type(result$samples, "double")
  expect_type(result$sample_rate, "integer")
  expect_type(result$num_samples, "integer")
})

test_that("read_wav fails with missing file", {
  expect_error(
    read_wav("nonexistent.wav"),
    "WAV file not found"
  )
})

test_that("OfflineRecognizer print shows quantization", {
  skip_on_cran()

  # Create recognizer with quantization suffix
  rec <- OfflineRecognizer$new(model = "whisper-tiny.en:int8", verbose = FALSE)

  # Capture print output
  output <- capture.output(print(rec))
  output_text <- paste(output, collapse = "\n")

  # Should show (int8) in model line
  expect_match(output_text, "\\(int8\\)")

  # Should show OfflineRecognizer header
  expect_match(output_text, "<OfflineRecognizer>")
})

test_that("OfflineRecognizer print doesn't show quantization when not used", {
  skip_on_cran()

  # Create recognizer without quantization
  rec <- OfflineRecognizer$new(model = "whisper-tiny.en", verbose = FALSE)

  # Capture print output
  output <- capture.output(print(rec))
  output_text <- paste(output, collapse = "\n")

  # Should NOT show (int8) in model line
  expect_false(grepl("\\(int8\\)", output_text))

  # Should show OfflineRecognizer header
  expect_match(output_text, "<OfflineRecognizer>")
})

test_that("OfflineRecognizer model_info contains quantization field", {
  skip_on_cran()

  # Create recognizer with quantization
  rec <- OfflineRecognizer$new(model = "whisper-tiny.en:int8", verbose = FALSE)
  info <- rec$model_info()

  expect_type(info, "list")
  expect_true("quantization" %in% names(info))
  expect_equal(info$quantization, "int8")

  # Create recognizer without quantization
  rec2 <- OfflineRecognizer$new(model = "whisper-tiny.en", verbose = FALSE)
  info2 <- rec2$model_info()

  expect_type(info2, "list")
  expect_true("quantization" %in% names(info2))
  expect_null(info2$quantization)
})
