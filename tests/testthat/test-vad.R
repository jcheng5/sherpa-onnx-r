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

# Tests for standalone vad() function

test_that("vad() function works with test audio", {
  skip_on_cran()
  skip_if_not(
    file.exists(system.file("extdata", "test.wav", package = "sherpa.onnx")),
    "test.wav not available"
  )

  result <- vad(
    system.file("extdata", "test.wav", package = "sherpa.onnx"),
    verbose = FALSE
  )

  # Check structure
  expect_s3_class(result, "sherpa_vad_result")
  expect_true(result$num_segments > 0)
  expect_equal(length(result$segments), result$num_segments)
  expect_equal(result$sample_rate, 16000)

  # Check segment structure
  seg <- result$segments[[1]]
  expect_true("samples" %in% names(seg))
  expect_true("start_time" %in% names(seg))
  expect_true("duration" %in% names(seg))
  expect_true(length(seg$samples) > 0)
  expect_true(seg$start_time >= 0)
  expect_true(seg$duration > 0)
})

test_that("vad() parameter validation works", {
  skip_on_cran()
  test_wav <- system.file("extdata", "test.wav", package = "sherpa.onnx")
  skip_if_not(file.exists(test_wav), "test.wav not available")

  # Invalid threshold
  expect_error(vad(test_wav, threshold = 1.5), "threshold must be between 0 and 1")
  expect_error(vad(test_wav, threshold = -0.1), "threshold must be between 0 and 1")

  # Negative parameters

  expect_error(vad(test_wav, min_silence = -1), "min_silence must be non-negative")
  expect_error(vad(test_wav, min_speech = -1), "min_speech must be non-negative")
  expect_error(vad(test_wav, max_speech = 0), "max_speech must be positive")

  # Non-existent file
  expect_error(vad("/nonexistent/file.wav"), "WAV file not found")
})

test_that("vad() print method works", {
  skip_on_cran()
  skip_if_not(
    file.exists(system.file("extdata", "test.wav", package = "sherpa.onnx")),
    "test.wav not available"
  )

  result <- vad(
    system.file("extdata", "test.wav", package = "sherpa.onnx"),
    verbose = FALSE
  )

  output <- capture.output(print(result))
  expect_true(any(grepl("VAD:", output)))
  expect_true(any(grepl("segment", output)))
})

test_that("vad() summary method works", {
  skip_on_cran()
  skip_if_not(
    file.exists(system.file("extdata", "test.wav", package = "sherpa.onnx")),
    "test.wav not available"
  )

  result <- vad(
    system.file("extdata", "test.wav", package = "sherpa.onnx"),
    verbose = FALSE
  )

  output <- capture.output(summary(result))
  expect_true(any(grepl("Voice Activity Detection", output)))
  expect_true(any(grepl("Sample rate:", output)))
  expect_true(any(grepl("Timing Statistics:", output)))
})

test_that("vad() as.data.frame works", {
  skip_on_cran()
  skip_if_not(
    file.exists(system.file("extdata", "test.wav", package = "sherpa.onnx")),
    "test.wav not available"
  )

  result <- vad(
    system.file("extdata", "test.wav", package = "sherpa.onnx"),
    verbose = FALSE
  )

  df <- as.data.frame(result)
  expect_s3_class(df, "data.frame")
  expect_equal(nrow(df), result$num_segments)
  expect_true(all(c("segment", "start_time", "end_time", "duration", "num_samples") %in% names(df)))
})

test_that("vad_segment_samples() works", {
  skip_on_cran()
  skip_if_not(
    file.exists(system.file("extdata", "test.wav", package = "sherpa.onnx")),
    "test.wav not available"
  )

  result <- vad(
    system.file("extdata", "test.wav", package = "sherpa.onnx"),
    verbose = FALSE
  )

  # Get samples from first segment
  samples <- vad_segment_samples(result, 1)
  expect_type(samples, "double")
  expect_equal(length(samples), length(result$segments[[1]]$samples))

  # Invalid index
  expect_error(vad_segment_samples(result, 0), "segment_index must be between")
  expect_error(vad_segment_samples(result, 100), "segment_index must be between")
})
