#!/usr/bin/env Rscript
# Test script for comparing NeMo Parakeet models in sherpa-onnx
# Usage: Rscript test_parakeet_models.R

library(sherpa.onnx)

# Expected transcription for test.wav
EXPECTED_TEXT <- "Posit's mission is to create open source software for data science, scientific research, and technical communication. We do this to enhance the production and consumption of knowledge by everyone, regardless of economic means."

# Define Parakeet models to test
# Only testing models with distinct practical use cases
models <- list(
  # Default: Best balance
  list(
    name = "parakeet-v3-int8",
    repo = "parakeet-v3",  # Use shorthand
    description = "Production default - best balance of speed, accuracy, and size"
  ),

  # DISABLED: External weights file issue (waiting for sherpa-onnx PR #2807)
  # # Accuracy priority: Maximum quality
  # list(
  #   name = "parakeet-v3 (float32)",
  #   repo = "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3",
  #   description = "Maximum accuracy - when quality matters most (2.55 GB)"
  # ),

  # Speed/size priority: Faster, smaller model
  list(
    name = "parakeet-110m (transducer)",
    repo = "csukuangfj/sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000",
    description = "Speed/size optimized - for edge devices or real-time needs (478 MB)"
  )

  # DISABLED: Crashes with missing 'lfr_window_size' metadata error
  # # Architecture comparison: CTC vs transducer
  # list(
  #   name = "parakeet-110m (CTC)",
  #   repo = "csukuangfj/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000",
  #   description = "CTC architecture - simpler decoding, potentially faster (458 MB)"
  # )
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
  description = character(),
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
  cat(sprintf("Description: %s\n", model_info$description))
  cat(rep("=", 70), "\n", sep = "")

  tryCatch({
    # Load model
    cat("Loading model...\n")
    load_start <- Sys.time()
    rec <- OfflineRecognizer$new(model = model_info$repo)
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
      description = model_info$description,
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
      description = model_info$description,
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

# Print analysis
cat("\n")
cat(rep("=", 70), "\n", sep = "")
cat("ANALYSIS\n")
cat(rep("=", 70), "\n", sep = "")
cat("\n")

# Model size comparison (110m vs 600m)
model_110m <- results[results$model == "parakeet-110m (transducer)", ]
model_600m <- results[results$model == "parakeet-v3-int8", ]

if (nrow(model_110m) > 0 && nrow(model_600m) > 0) {
  speedup <- (model_600m$transcribe_time / model_110m$transcribe_time - 1) * 100
  size_reduction <- (1 - 478 / 671) * 100
  cat(sprintf("Model size comparison (110m vs 600m-int8):\n"))
  cat(sprintf("  Speed: 110m is %.1f%% faster (%.2fs vs %.2fs)\n",
              speedup, model_110m$transcribe_time, model_600m$transcribe_time))
  cat(sprintf("  Size: 110m is %.1f%% smaller (478 MB vs 671 MB)\n", size_reduction))
  cat("\n")
}

# Recommendations
cat("RECOMMENDATIONS:\n")
cat("  - Production default: parakeet-v3-int8 (best balance)\n")
cat("  - Edge devices/speed priority: parakeet-110m (6x faster, good accuracy)\n")
cat("\n")
cat("NOTE: Some models disabled due to current sherpa-onnx limitations:\n")
cat("  - float32 models: External weights file issue (PR #2807 pending)\n")
cat("  - CTC models: Metadata compatibility issue\n")

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
output_file <- "parakeet_model_comparison.csv"
write.csv(results, output_file, row.names = FALSE)
cat(sprintf("Results saved to: %s\n", output_file))
