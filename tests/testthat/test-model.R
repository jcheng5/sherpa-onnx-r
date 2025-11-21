test_that("shorthand models are defined", {
  models <- available_models()
  expect_true(length(models) > 0)
  expect_true("whisper-tiny" %in% models)
  expect_true("parakeet-v3" %in% models)
})

test_that("detect_model_type works for whisper", {
  # Create a temporary directory with whisper files
  temp_dir <- tempdir()
  model_dir <- file.path(temp_dir, "test_whisper")
  dir.create(model_dir, showWarnings = FALSE)

  # Create dummy files
  file.create(file.path(model_dir, "encoder.onnx"))
  file.create(file.path(model_dir, "decoder.onnx"))
  file.create(file.path(model_dir, "tokens.txt"))

  model_type <- detect_model_type(model_dir)
  expect_equal(model_type, "whisper")

  # Cleanup
  unlink(model_dir, recursive = TRUE)
})

test_that("detect_model_type works for transducer", {
  temp_dir <- tempdir()
  model_dir <- file.path(temp_dir, "test_transducer")
  dir.create(model_dir, showWarnings = FALSE)

  file.create(file.path(model_dir, "encoder.onnx"))
  file.create(file.path(model_dir, "decoder.onnx"))
  file.create(file.path(model_dir, "joiner.onnx"))
  file.create(file.path(model_dir, "tokens.txt"))

  model_type <- detect_model_type(model_dir)
  expect_equal(model_type, "transducer")

  unlink(model_dir, recursive = TRUE)
})

test_that("detect_model_type works for paraformer", {
  temp_dir <- tempdir()
  model_dir <- file.path(temp_dir, "test_paraformer")
  dir.create(model_dir, showWarnings = FALSE)

  file.create(file.path(model_dir, "model.onnx"))
  file.create(file.path(model_dir, "tokens.txt"))

  model_type <- detect_model_type(model_dir)
  expect_equal(model_type, "paraformer")

  unlink(model_dir, recursive = TRUE)
})

test_that("cache_dir returns a valid path", {
  cache <- cache_dir()
  expect_true(nzchar(cache))
  expect_true(dir.exists(dirname(cache)))
})

test_that("is_valid_model_dir checks correctly", {
  temp_dir <- tempdir()
  model_dir <- file.path(temp_dir, "test_model")
  dir.create(model_dir, showWarnings = FALSE)

  # Invalid - no files
  expect_false(is_valid_model_dir(model_dir))

  # Invalid - only onnx
  file.create(file.path(model_dir, "model.onnx"))
  expect_false(is_valid_model_dir(model_dir))

  # Valid - has both onnx and tokens
  file.create(file.path(model_dir, "tokens.txt"))
  expect_true(is_valid_model_dir(model_dir))

  unlink(model_dir, recursive = TRUE)
})
