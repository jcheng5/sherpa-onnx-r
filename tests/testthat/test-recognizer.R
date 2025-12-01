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
  skip_if_not(file.exists("../test.wav"), "Test WAV not available")

  result <- read_wav("../test.wav")

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
