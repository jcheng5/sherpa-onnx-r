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

test_that("new Whisper model shorthands are available", {
  models <- available_models()

  # English-only models (with .en suffix)
  expect_true("whisper-tiny.en" %in% models)
  expect_true("whisper-base.en" %in% models)
  expect_true("whisper-small.en" %in% models)
  expect_true("whisper-medium.en" %in% models)

  # Multilingual models (no .en suffix)
  expect_true("whisper-tiny" %in% models)
  expect_true("whisper-base" %in% models)
  expect_true("whisper-small" %in% models)
  expect_true("whisper-medium" %in% models)

  # Large variants
  expect_true("whisper-large" %in% models)
  expect_true("whisper-large-v1" %in% models)
  expect_true("whisper-large-v2" %in% models)
  expect_true("whisper-large-v3" %in% models)
  expect_true("whisper-turbo" %in% models)

  # Distilled models
  expect_true("whisper-distil-small.en" %in% models)
  expect_true("whisper-distil-medium.en" %in% models)
  expect_true("whisper-distil-large-v2" %in% models)
  expect_true("whisper-distil-large-v3" %in% models)
  expect_true("whisper-distil-large-v3.5" %in% models)
})

test_that("resolve_model parses quantization suffix", {
  # Test int8 suffix parsing
  result <- resolve_model("whisper-tiny.en:int8", verbose = FALSE)
  expect_equal(result$quantization, "int8")

  # Test fp16 suffix parsing (future-proof)
  result <- resolve_model("whisper-tiny.en:fp16", verbose = FALSE)
  expect_equal(result$quantization, "fp16")

  # Test no suffix
  result <- resolve_model("whisper-tiny.en", verbose = FALSE)
  expect_null(result$quantization)
})

test_that("guess_model_files prefers quantized when requested", {
  temp_dir <- tempdir()
  model_dir <- file.path(temp_dir, "test_quant")
  dir.create(model_dir, showWarnings = FALSE)

  # Create both regular and int8 versions
  file.create(file.path(model_dir, "encoder.onnx"))
  file.create(file.path(model_dir, "encoder.int8.onnx"))
  file.create(file.path(model_dir, "decoder.onnx"))
  file.create(file.path(model_dir, "decoder.int8.onnx"))
  file.create(file.path(model_dir, "tokens.txt"))

  # Without quantization preference, should get regular
  files <- guess_model_files(model_dir, quantization = NULL)
  expect_equal(files$encoder, "encoder.onnx")
  expect_equal(files$decoder, "decoder.onnx")

  # With int8 preference, should get int8
  files <- guess_model_files(model_dir, quantization = "int8")
  expect_equal(files$encoder, "encoder.int8.onnx")
  expect_equal(files$decoder, "decoder.int8.onnx")

  unlink(model_dir, recursive = TRUE)
})

test_that("guess_model_files falls back when quantized not available", {
  temp_dir <- tempdir()
  model_dir <- file.path(temp_dir, "test_fallback")
  dir.create(model_dir, showWarnings = FALSE)

  # Create only regular versions
  file.create(file.path(model_dir, "encoder.onnx"))
  file.create(file.path(model_dir, "decoder.onnx"))
  file.create(file.path(model_dir, "tokens.txt"))

  # Request int8 but it doesn't exist - should fall back to regular
  files <- guess_model_files(model_dir, quantization = "int8")
  expect_equal(files$encoder, "encoder.onnx")
  expect_equal(files$decoder, "decoder.onnx")

  unlink(model_dir, recursive = TRUE)
})

test_that("guess_model_files handles multiple quantization types", {
  temp_dir <- tempdir()
  model_dir <- file.path(temp_dir, "test_multi_quant")
  dir.create(model_dir, showWarnings = FALSE)

  # Create regular, int8, and fp16 versions
  file.create(file.path(model_dir, "model.onnx"))
  file.create(file.path(model_dir, "model.int8.onnx"))
  file.create(file.path(model_dir, "model.fp16.onnx"))
  file.create(file.path(model_dir, "tokens.txt"))

  # Request int8
  files <- guess_model_files(model_dir, quantization = "int8")
  expect_equal(files$model, "model.int8.onnx")

  # Request fp16
  files <- guess_model_files(model_dir, quantization = "fp16")
  expect_equal(files$model, "model.fp16.onnx")

  # Request int4 (doesn't exist, should fall back)
  files <- guess_model_files(model_dir, quantization = "int4")
  expect_equal(files$model, "model.onnx")

  unlink(model_dir, recursive = TRUE)
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
