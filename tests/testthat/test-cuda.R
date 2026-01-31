# Tests for CUDA support detection

test_that("cuda_available returns logical", {
  result <- cuda_available()
  expect_type(result, "logical")
  expect_length(result, 1)
})

test_that("cuda_available doesn't error", {
  expect_no_error(cuda_available())
})

test_that("OfflineRecognizer respects provider parameter", {
  skip_on_cran()

  # CPU provider should always work
  rec_cpu <- OfflineRecognizer$new(
    model = "whisper-tiny.en",
    provider = "cpu",
    verbose = FALSE
  )

  output <- capture.output(print(rec_cpu))
  output_text <- paste(output, collapse = "\n")
  expect_match(output_text, "Provider: cpu")
})

test_that("OfflineRecognizer with CUDA provider works when available", {
  skip_on_cran()
  skip_if_not(cuda_available(), "CUDA not available")

  # CUDA provider should work if CUDA is available
  expect_no_error({
    rec_cuda <- OfflineRecognizer$new(
      model = "whisper-tiny.en",
      provider = "cuda",
      verbose = FALSE
    )
  })

  rec_cuda <- OfflineRecognizer$new(
    model = "whisper-tiny.en",
    provider = "cuda",
    verbose = FALSE
  )

  output <- capture.output(print(rec_cuda))
  output_text <- paste(output, collapse = "\n")
  expect_match(output_text, "Provider: cuda")
})
