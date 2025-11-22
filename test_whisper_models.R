#!/usr/bin/env Rscript
# Test script for comparing all Whisper models in sherpa-onnx
# Usage: Rscript test_whisper_models.R

library(sherpa.onnx)

# Expected transcription for test.wav
EXPECTED_TEXT <- "Posit's mission is to create open source software for data science, scientific research, and technical communication. We do this to enhance the production and consumption of knowledge by everyone, regardless of economic means."

# Define all Whisper models to test
models <- list(
  # English-only models
  list(name = "whisper-tiny.en", repo = "whisper-tiny"),
  list(name = "whisper-base.en", repo = "whisper-base"),
  list(name = "whisper-small.en", repo = "csukuangfj/sherpa-onnx-whisper-small.en"),
  list(name = "whisper-medium.en", repo = "csukuangfj/sherpa-onnx-whisper-medium.en"),

  # Multilingual models (require explicit language)
  list(name = "whisper-tiny (multilingual)", repo = "csukuangfj/sherpa-onnx-whisper-tiny", language = "en"),
  list(name = "whisper-base (multilingual)", repo = "csukuangfj/sherpa-onnx-whisper-base", language = "en"),
  list(name = "whisper-medium (multilingual)", repo = "csukuangfj/sherpa-onnx-whisper-medium", language = "en"),
  # DISABLED: External weights file issue (waiting for sherpa-onnx PR #2807)
  # list(name = "whisper-large-v2", repo = "csukuangfj/sherpa-onnx-whisper-large-v2", language = "en"),
  # list(name = "whisper-large-v3", repo = "csukuangfj/sherpa-onnx-whisper-large-v3", language = "en"),

  # Distilled models
  list(name = "whisper-distil-small.en", repo = "csukuangfj/sherpa-onnx-whisper-distil-small.en"),
  list(name = "whisper-distil-medium.en", repo = "csukuangfj/sherpa-onnx-whisper-distil-medium.en")
  # DISABLED: External weights file issue (waiting for sherpa-onnx PR #2807)
  # list(name = "whisper-distil-large-v3", repo = "csukuangfj/sherpa-onnx-whisper-distil-large-v3")
)

# Test audio file
# Try installed location first, then development location
audio_file <- system.file("extdata", "test.wav", package = "sherpa.onnx")
if (audio_file == "" || !file.exists(audio_file)) {
  audio_file <- "inst/extdata/test.wav"
}

if (!file.exists(audio_file)) {
  stop("Audio file not found: ", audio_file)
}

# Initialize results dataframe
results <- data.frame(
  model = character(),
  load_time = numeric(),
  transcribe_time = numeric(),
  total_time = numeric(),
  text = character(),
  stringsAsFactors = FALSE
)

# Test each model
for (i in seq_along(models)) {
  model_info <- models[[i]]
  cat("\n")
  cat(rep("=", 70), "\n", sep = "")
  cat(sprintf("Testing model %d/%d: %s\n", i, length(models), model_info$name))
  cat(rep("=", 70), "\n", sep = "")

  tryCatch({
    # Load model
    cat("Loading model...\n")
    load_start <- Sys.time()
    # Use language parameter if specified, otherwise use default "auto"
    if (!is.null(model_info$language)) {
      rec <- OfflineRecognizer$new(model = model_info$repo, language = model_info$language)
    } else {
      rec <- OfflineRecognizer$new(model = model_info$repo)
    }
    load_time <- as.numeric(difftime(Sys.time(), load_start, units = "secs"))
    cat(sprintf("✓ Model loaded in %.2f seconds\n", load_time))

    # Transcribe
    cat("Transcribing audio...\n")
    transcribe_start <- Sys.time()
    result <- rec$transcribe(audio_file)
    transcribe_time <- as.numeric(difftime(Sys.time(), transcribe_start, units = "secs"))
    cat(sprintf("✓ Transcription completed in %.2f seconds\n", transcribe_time))

    # Store results
    total_time <- load_time + transcribe_time
    results <- rbind(results, data.frame(
      model = model_info$name,
      load_time = load_time,
      transcribe_time = transcribe_time,
      total_time = total_time,
      text = trimws(result$text),
      stringsAsFactors = FALSE
    ))

    cat("\nTranscription:\n")
    cat(result$text, "\n")

  }, error = function(e) {
    cat(sprintf("✗ ERROR: %s\n", e$message))
    results <<- rbind(results, data.frame(
      model = model_info$name,
      load_time = NA,
      transcribe_time = NA,
      total_time = NA,
      text = sprintf("ERROR: %s", e$message),
      stringsAsFactors = FALSE
    ))
  })
}

# Print summary table
cat("\n")
cat(rep("=", 70), "\n", sep = "")
cat("SUMMARY OF RESULTS\n")
cat(rep("=", 70), "\n", sep = "")
cat("\n")

# Create summary table
summary_table <- results[, c("model", "load_time", "transcribe_time", "total_time")]
summary_table$load_time <- sprintf("%.2fs", summary_table$load_time)
summary_table$transcribe_time <- sprintf("%.2fs", summary_table$transcribe_time)
summary_table$total_time <- sprintf("%.2fs", summary_table$total_time)

print(summary_table, row.names = FALSE)

cat("\n")
cat(rep("=", 70), "\n", sep = "")
cat("TRANSCRIPTION COMPARISON\n")
cat(rep("=", 70), "\n", sep = "")
cat("\n")

cat("Expected:\n")
cat(EXPECTED_TEXT, "\n\n")

for (i in 1:nrow(results)) {
  cat(sprintf("%s:\n", results$model[i]))
  cat(results$text[i], "\n\n")
}

# Save results to CSV
output_file <- "whisper_model_comparison.csv"
write.csv(results, output_file, row.names = FALSE)
cat(sprintf("Results saved to: %s\n", output_file))
