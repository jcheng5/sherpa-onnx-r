# Utility functions for sherpa.onnx R package

#' Read a WAV file
#'
#' @param wav_path Path to WAV file
#' @return List with samples, sample_rate, and num_samples
#' @noRd
read_wav <- function(wav_path) {
  # Expand tilde and other path shortcuts
  wav_path <- path.expand(wav_path)

  if (!file.exists(wav_path)) {
    stop("WAV file not found: ", wav_path)
  }

  read_wav_(wav_path)
}

#' Check if a path is a valid model directory
#'
#' @param path Path to check
#' @return Logical indicating if path contains model files
#' @noRd
is_valid_model_dir <- function(path) {
  if (!dir.exists(path)) {
    return(FALSE)
  }

  files <- list.files(path)

  # Check for any ONNX model files
  has_onnx <- any(grepl("\\.onnx$", files))

  # Check for tokens file
  has_tokens <- "tokens.txt" %in% files

  return(has_onnx && has_tokens)
}

#' Format file size for display
#'
#' @param bytes Number of bytes
#' @return Formatted string (e.g., "1.5 MB")
#' @noRd
format_bytes <- function(bytes) {
  if (bytes < 1024) {
    return(sprintf("%d B", bytes))
  } else if (bytes < 1024^2) {
    return(sprintf("%.1f KB", bytes / 1024))
  } else if (bytes < 1024^3) {
    return(sprintf("%.1f MB", bytes / 1024^2))
  } else {
    return(sprintf("%.1f GB", bytes / 1024^3))
  }
}

#' List available shorthand models
#'
#' @return Character vector of available model shorthands
#' @export
#'
#' @examples
#' available_models()
available_models <- function() {
  names(SHORTHAND_MODELS)
}

#' Get cache directory path
#'
#' @return Path to cache directory
#' @export
#'
#' @examples
#' cache_dir()
cache_dir <- function() {
  get_cache_dir()
}

#' Clear model cache
#'
#' @param confirm Logical, if TRUE will prompt for confirmation
#' @return Logical indicating success
#' @export
#'
#' @examples
#' \dontrun{
#' clear_cache(confirm = FALSE)
#' }
clear_cache <- function(confirm = TRUE) {
  cache_path <- get_cache_dir()

  if (!dir.exists(cache_path)) {
    message("Cache directory does not exist: ", cache_path)
    return(TRUE)
  }

  if (confirm) {
    response <- readline(
      prompt = sprintf("Delete cache directory %s? (yes/no): ", cache_path)
    )

    if (tolower(response) != "yes") {
      message("Cache clearing cancelled")
      return(FALSE)
    }
  }

  success <- unlink(cache_path, recursive = TRUE) == 0

  if (success) {
    message("Cache cleared successfully")
  } else {
    warning("Failed to clear cache")
  }

  return(success)
}
