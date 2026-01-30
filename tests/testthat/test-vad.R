# Tests for VAD (Voice Activity Detection) transcription

test_that("VAD model auto-downloads", {
  # This should trigger download if not cached
  vad_path <- download_vad_model("silero-vad", verbose = FALSE)

  expect_true(file.exists(vad_path))
  expect_match(vad_path, "silero_vad\\.onnx$")
})

test_that("VAD model handles local paths", {
  # First ensure model is downloaded

  vad_path <- download_vad_model("silero-vad", verbose = FALSE)

  # Now use it as a local path
  local_result <- download_vad_model(vad_path, verbose = FALSE)
  expect_equal(normalizePath(local_result), normalizePath(vad_path))
})

test_that("VAD model rejects invalid paths", {
  expect_error(
    download_vad_model("/nonexistent/path/to/model.onnx", verbose = FALSE),
    "VAD model not found"
  )
})

test_that("VAD parameters are validated", {
  skip_on_cran()
  skip_if_not(
    file.exists(system.file("extdata", "test.wav", package = "sherpa.onnx")),
    "test.wav not available"
  )

  rec <- OfflineRecognizer$new(model = "whisper-tiny", verbose = FALSE)
  test_wav <- system.file("extdata", "test.wav", package = "sherpa.onnx")

  # Invalid threshold (too high)
  expect_error(
    rec$transcribe(test_wav, use_vad = TRUE, vad_threshold = 1.5),
    "vad_threshold must be between 0 and 1"
  )

  # Invalid threshold (too low)
  expect_error(
    rec$transcribe(test_wav, use_vad = TRUE, vad_threshold = -0.1),
    "vad_threshold must be between 0 and 1"
  )

  # Negative min_silence
  expect_error(
    rec$transcribe(test_wav, use_vad = TRUE, vad_min_silence = -1),
    "vad_min_silence must be non-negative"
  )

  # Negative min_speech
  expect_error(
    rec$transcribe(test_wav, use_vad = TRUE, vad_min_speech = -1),
    "vad_min_speech must be non-negative"
  )

  # Non-positive max_speech
  expect_error(
    rec$transcribe(test_wav, use_vad = TRUE, vad_max_speech = 0),
    "vad_max_speech must be positive"
  )
})

test_that("VAD transcription works with test audio", {
  skip_on_cran()
  skip_if_not(
    file.exists(system.file("extdata", "test.wav", package = "sherpa.onnx")),
    "test.wav not available"
  )

  rec <- OfflineRecognizer$new(model = "whisper-tiny", verbose = FALSE)

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

  # Timing should be valid
  expect_true(all(result$segment_starts >= 0))
  expect_true(all(result$segment_durations > 0))
})

test_that("VAD transcription returns consistent text", {
  skip_on_cran()
  skip_if_not(
    file.exists(system.file("extdata", "test.wav", package = "sherpa.onnx")),
    "test.wav not available"
  )

  rec <- OfflineRecognizer$new(model = "whisper-tiny", verbose = FALSE)
  test_wav <- system.file("extdata", "test.wav", package = "sherpa.onnx")

  # Transcribe with and without VAD
  result_plain <- rec$transcribe(test_wav)
  result_vad <- rec$transcribe(test_wav, use_vad = TRUE, verbose = FALSE)

  # Both should produce non-empty text
  expect_true(nchar(result_plain$text) > 0)
  expect_true(nchar(result_vad$text) > 0)

  # Text content should be similar (not exact due to different processing)
  # Just check that both contain some common words
  plain_words <- tolower(strsplit(result_plain$text, "\\s+")[[1]])
  vad_words <- tolower(strsplit(result_vad$text, "\\s+")[[1]])

  # There should be some overlap in words
  common_words <- intersect(plain_words, vad_words)
  expect_true(length(common_words) > 0)
})

test_that("VAD print method shows segment count", {
  skip_on_cran()
  skip_if_not(
    file.exists(system.file("extdata", "test.wav", package = "sherpa.onnx")),
    "test.wav not available"
  )

  rec <- OfflineRecognizer$new(model = "whisper-tiny", verbose = FALSE)

  result <- rec$transcribe(
    system.file("extdata", "test.wav", package = "sherpa.onnx"),
    use_vad = TRUE,
    verbose = FALSE
  )

  # Capture print output
  output <- capture.output(print(result))

  # Should contain segment count in metadata
  expect_true(any(grepl("segment", output, ignore.case = TRUE)))
})

test_that("VAD summary method shows segmentation info", {
  skip_on_cran()
  skip_if_not(
    file.exists(system.file("extdata", "test.wav", package = "sherpa.onnx")),
    "test.wav not available"
  )

  rec <- OfflineRecognizer$new(model = "whisper-tiny", verbose = FALSE)

  result <- rec$transcribe(
    system.file("extdata", "test.wav", package = "sherpa.onnx"),
    use_vad = TRUE,
    verbose = FALSE
  )

  # Capture summary output
  output <- capture.output(summary(result))

  # Should contain VAD-specific info
  expect_true(any(grepl("VAD Segmentation", output)))
  expect_true(any(grepl("Segments:", output)))
})
