#' S3 Class for Sherpa-ONNX Transcription Results
#'
#' @description
#' The `sherpa_transcription` class wraps transcription results from
#' `OfflineRecognizer$transcribe()` with user-friendly print and summary methods.
#' The object behaves like a list, maintaining full backward compatibility with
#' existing code that accesses fields via `result$field`.
#'
#' @name sherpa_transcription
NULL

#' Create a sherpa_transcription object
#'
#' @param result_list List containing transcription results from C++ layer
#' @param model_info Model metadata from resolve_model()
#'
#' @return A sherpa_transcription object (S3 class inheriting from list)
#' @keywords internal
new_sherpa_transcription <- function(result_list, model_info) {
  structure(
    result_list,
    class = c("sherpa_transcription", "list"),
    model_info = model_info
  )
}

#' Extract model display name from model_info
#'
#' @param model_info Model metadata list
#' @return Character string with friendly model name
#' @keywords internal
extract_model_display_name <- function(model_info) {
  if (is.null(model_info)) return("")

  # Priority: shorthand name > repo name > basename of path
  if (!is.null(model_info$shorthand)) {
    return(model_info$shorthand)
  } else if (!is.null(model_info$repo)) {
    # Extract friendly name from repo (e.g., "csukuangfj/sherpa-onnx-whisper-tiny.en" -> "whisper-tiny.en")
    repo_parts <- strsplit(model_info$repo, "/")[[1]]
    repo_name <- repo_parts[length(repo_parts)]
    # Remove common prefixes
    repo_name <- sub("^sherpa-onnx-", "", repo_name)
    return(repo_name)
  } else if (!is.null(model_info$path)) {
    return(basename(model_info$path))
  }

  return("")
}

#' Print method for sherpa_transcription
#'
#' @param x A sherpa_transcription object
#' @param ... Additional arguments (ignored)
#'
#' @return The object invisibly
#'
#' @details
#' Prints a clean, user-friendly representation with:
#' - Metadata line: `[N tokens | model-name]` or `[N segments | model-name]` for VAD
#' - Blank line
#' - Full transcription text
#'
#' @examples
#' \dontrun{
#' rec <- OfflineRecognizer$new(model = "whisper-tiny")
#' result <- rec$transcribe("audio.wav")
#' print(result)
#' # [39 tokens | whisper-tiny]
#' #
#' # Posit's mission is to create open source software...
#' }
#'
#' @export
print.sherpa_transcription <- function(x, ...) {
  # Extract model name from stored attribute
  model_info <- attr(x, "model_info")
  model_name <- extract_model_display_name(model_info)

  # Build metadata parts
  metadata_parts <- character()

  # Token count (if available, for non-VAD results)
  if (!is.null(x$tokens) && length(x$tokens) > 0) {
    metadata_parts <- c(metadata_parts, sprintf("%d tokens", length(x$tokens)))
  }

  # Segment count (if VAD was used)
  if (!is.null(x$num_segments) && x$num_segments > 0) {
    metadata_parts <- c(metadata_parts, sprintf("%d segments", x$num_segments))
  }

  # Model name
  if (!is.null(model_name) && model_name != "") {
    metadata_parts <- c(metadata_parts, model_name)
  }

  # Print metadata line
  if (length(metadata_parts) > 0) {
    cat(sprintf("[%s]\n", paste(metadata_parts, collapse = " | ")))
  }

  # Blank line
  cat("\n")

  # Print full text
  cat(x$text, "\n", sep = "")

  invisible(x)
}

#' Convert sherpa_transcription to character
#'
#' @param x A sherpa_transcription object
#' @param ... Additional arguments (ignored)
#'
#' @return Character string containing the transcription text
#'
#' @details
#' Extracts just the text field from the transcription result, useful for
#' piping or when you need the text as a simple string.
#'
#' @examples
#' \dontrun{
#' rec <- OfflineRecognizer$new(model = "whisper-tiny")
#' result <- rec$transcribe("audio.wav")
#' text <- as.character(result)
#' # Returns just the transcription text string
#' }
#'
#' @export
as.character.sherpa_transcription <- function(x, ...) {
  x$text
}

#' Summary method for sherpa_transcription
#'
#' @param object A sherpa_transcription object
#' @param ... Additional arguments (ignored)
#'
#' @return The object invisibly
#'
#' @details
#' Displays detailed information about the transcription including:
#' - Model information (name, repo)
#' - Text statistics (character count, word count, token count)
#' - VAD segmentation info (if applicable)
#' - Available fields with types and previews
#' - First few tokens
#'
#' @examples
#' \dontrun{
#' rec <- OfflineRecognizer$new(model = "whisper-tiny")
#' result <- rec$transcribe("audio.wav")
#' summary(result)
#' # Shows detailed statistics and field information
#' }
#'
#' @export
summary.sherpa_transcription <- function(object, ...) {
  cat("Sherpa-ONNX Transcription\n")
  cat("=========================\n\n")

  # Model info
  model_info <- attr(object, "model_info")
  if (!is.null(model_info)) {
    model_name <- extract_model_display_name(model_info)
    if (!is.null(model_info$repo)) {
      cat(sprintf("Model: %s (%s)\n", model_name, model_info$repo))
    } else {
      cat(sprintf("Model: %s\n", model_name))
    }
  }
  cat("\n")

  # Text statistics
  cat("Text Statistics:\n")
  cat(sprintf("  Characters: %d\n", nchar(object$text)))

  # Count words (split on whitespace)
  words <- strsplit(trimws(object$text), "\\s+")[[1]]
  cat(sprintf("  Words: %d\n", length(words)))

  token_count <- if (!is.null(object$tokens)) length(object$tokens) else 0
  if (token_count > 0) {
    cat(sprintf("  Tokens: %d\n", token_count))
  }
  cat("\n")

  # VAD segment info (if available)
  if (!is.null(object$num_segments) && object$num_segments > 0) {
    cat("VAD Segmentation:\n")
    cat(sprintf("  Segments: %d\n", object$num_segments))
    if (!is.null(object$segment_starts) && length(object$segment_starts) > 0 &&
        !is.null(object$segment_durations) && length(object$segment_durations) > 0) {
      total_duration <- max(object$segment_starts + object$segment_durations)
      speech_duration <- sum(object$segment_durations)
      cat(sprintf("  Total duration: %.1f sec\n", total_duration))
      cat(sprintf("  Speech duration: %.1f sec\n", speech_duration))
      cat(sprintf("  Speech ratio: %.1f%%\n", 100 * speech_duration / total_duration))
    }
    cat("\n")
  }

  # Available fields
  cat("Available Fields:\n")
  for (field_name in names(object)) {
    value <- object[[field_name]]
    if (is.null(value)) {
      cat(sprintf("  %-20s: NULL\n", field_name))
    } else if (is.character(value) && length(value) == 1) {
      display_val <- if (nchar(value) > 50) {
        paste0(substr(value, 1, 47), "...")
      } else {
        value
      }
      cat(sprintf("  %-20s: chr \"%s\"\n", field_name, display_val))
    } else if (is.character(value)) {
      cat(sprintf("  %-20s: chr[%d]\n", field_name, length(value)))
    } else if (is.numeric(value) && length(value) == 1) {
      cat(sprintf("  %-20s: num %s\n", field_name, format(value, digits = 3)))
    } else if (is.numeric(value)) {
      cat(sprintf("  %-20s: num[%d]\n", field_name, length(value)))
    } else {
      cat(sprintf("  %-20s: %s\n", field_name, class(value)[1]))
    }
  }

  # Show first few tokens if available
  if (!is.null(object$tokens) && length(object$tokens) > 0) {
    cat("\nFirst", min(5, length(object$tokens)), "tokens:",
        paste(shQuote(head(object$tokens, 5), type = "cmd"), collapse = ", "), "\n")
  }

  invisible(object)
}
