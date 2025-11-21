# Model management functions for sherpa.onnx R package
# Handles model resolution, downloading, and type detection

# Shorthand model mappings
SHORTHAND_MODELS <- list(
  "parakeet-v3" = "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
  "whisper-tiny" = "csukuangfj/sherpa-onnx-whisper-tiny.en",
  "whisper-base" = "csukuangfj/sherpa-onnx-whisper-base.en",
  "sense-voice" = "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
)

#' Resolve model specification to local path
#'
#' @param model Model specification (shorthand, HF repo, or local path)
#' @param verbose Logical, whether to print messages
#' @return List with type, path, and model_type
#' @keywords internal
resolve_model <- function(model = "parakeet-v3", verbose = TRUE) {
  # 1. Check if it's a local path
  if (dir.exists(model)) {
    if (verbose) message("Using local model at: ", model)
    return(list(
      type = "local",
      path = normalizePath(model, mustWork = TRUE),
      model_type = detect_model_type(model)
    ))
  }

  # 2. Check if it's a HuggingFace repo (contains "/")
  if (grepl("/", model, fixed = TRUE)) {
    hf_repo <- model
  } else {
    # 3. Treat as shorthand
    hf_repo <- SHORTHAND_MODELS[[model]]
    if (is.null(hf_repo)) {
      stop(
        "Unknown model shorthand: ", model,
        "\nAvailable: ", paste(names(SHORTHAND_MODELS), collapse = ", ")
      )
    }
    if (verbose) message("Using model: ", model, " (", hf_repo, ")")
  }

  # Download from HuggingFace (or use cache)
  model_path <- download_hf_model(hf_repo, verbose = verbose)

  return(list(
    type = "huggingface",
    repo = hf_repo,
    path = model_path,
    model_type = detect_model_type(model_path)
  ))
}

#' Download model from HuggingFace Hub
#'
#' @param repo HuggingFace repository (e.g., "csukuangfj/sherpa-onnx-whisper-tiny.en")
#' @param verbose Logical, whether to print messages
#' @return Local path to downloaded model
#' @keywords internal
download_hf_model <- function(repo, verbose = TRUE) {
  # First, try to use cached version
  model_path <- tryCatch({
    hfhub::hub_snapshot(
      repo,
      ignore_patterns = c("test_wavs/*", ".gitattributes", "*.md"),
      local_files_only = TRUE
    )
  }, error = function(e) NULL)

  if (!is.null(model_path)) {
    # Model found in cache
    if (verbose) message("Loading cached model from: ", basename(dirname(model_path)))
  } else {
    # Need to download
    if (verbose) {
      message("Downloading model from HuggingFace: ", repo)
      message("This may take a few minutes...")
    }

    model_path <- hfhub::hub_snapshot(
      repo,
      ignore_patterns = c("test_wavs/*", ".gitattributes", "*.md")
    )

    if (verbose) message("Model downloaded and cached")
  }

  # Create symlinks for standard file names if needed
  # sherpa-onnx models may use custom names like tiny.en-encoder.onnx
  # We need to create symlinks to encoder.onnx, decoder.onnx, tokens.txt
  create_standard_symlinks(model_path)

  return(model_path)
}

#' Create standard symlinks for model files
#'
#' @param model_dir Path to model directory
#' @keywords internal
create_standard_symlinks <- function(model_dir) {
  files <- list.files(model_dir)

  # Helper to find best candidate (prefer non-int8, then any)
  find_best_candidate <- function(pattern) {
    candidates <- grep(pattern, files, value = TRUE)
    if (length(candidates) == 0) return(NULL)

    # Prefer non-int8 versions if available
    non_int8 <- candidates[!grepl("int8", candidates)]
    if (length(non_int8) > 0) {
      return(non_int8[1])
    }

    # Otherwise use int8 version
    return(candidates[1])
  }

  # Create encoder.onnx symlink if it doesn't exist
  if (!"encoder.onnx" %in% files) {
    candidate <- find_best_candidate("encoder\\.onnx$")
    if (!is.null(candidate)) {
      file.symlink(basename(candidate), file.path(model_dir, "encoder.onnx"))
    }
  }

  # Create decoder.onnx symlink if it doesn't exist
  if (!"decoder.onnx" %in% files) {
    candidate <- find_best_candidate("decoder\\.onnx$")
    if (!is.null(candidate)) {
      file.symlink(basename(candidate), file.path(model_dir, "decoder.onnx"))
    }
  }

  # Create joiner.onnx symlink if it doesn't exist (for transducer models)
  if (!"joiner.onnx" %in% files) {
    candidate <- find_best_candidate("joiner\\.onnx$")
    if (!is.null(candidate)) {
      file.symlink(basename(candidate), file.path(model_dir, "joiner.onnx"))
    }
  }

  # Create tokens.txt symlink if it doesn't exist
  if (!"tokens.txt" %in% files) {
    tokens_candidates <- grep("-tokens\\.txt$", files, value = TRUE)
    if (length(tokens_candidates) > 0) {
      file.symlink(
        basename(tokens_candidates[1]),
        file.path(model_dir, "tokens.txt")
      )
    }
  }
}

#' Detect model type from files in directory
#'
#' @param model_dir Path to model directory
#' @return String indicating model type
#' @keywords internal
detect_model_type <- function(model_dir) {
  files <- list.files(model_dir)

  # Helper to check if file exists (including .int8 versions)
  has_file <- function(name) {
    name %in% files || any(grepl(paste0("^", name, "$"), files)) ||
      any(grepl(paste0(gsub("\\.onnx$", "\\.int8\\.onnx$", name)), files))
  }

  # Check for transducer (encoder + decoder + joiner)
  if (has_file("encoder.onnx") &&
      has_file("decoder.onnx") &&
      has_file("joiner.onnx")) {
    return("transducer")
  }

  # Check for whisper (encoder + decoder, no joiner)
  if (has_file("encoder.onnx") && has_file("decoder.onnx")) {
    return("whisper")
  }

  # Check for paraformer or sense-voice (single model.onnx)
  if (any(grepl("^model.*\\.onnx$", files))) {
    # Check for sense-voice indicators
    if (any(grepl("sense-?voice", model_dir, ignore.case = TRUE)) ||
        any(grepl("sense-?voice", files, ignore.case = TRUE))) {
      return("sense-voice")
    } else {
      return("paraformer")
    }
  }

  stop(
    "Could not detect model type from files in: ", model_dir,
    "\nFiles found: ", paste(files, collapse = ", ")
  )
}

#' Get cache directory for models
#'
#' @return Path to cache directory
#' @keywords internal
get_cache_dir <- function() {
  # Check for user-specified cache directory
  cache_env <- Sys.getenv("SHERPA_ONNX_CACHE_DIR")
  if (nzchar(cache_env)) {
    return(cache_env)
  }

  # Use rappdirs for platform-appropriate cache location
  cache_dir <- rappdirs::user_cache_dir("sherpa-onnx-r")

  # Create if doesn't exist
  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  }

  return(cache_dir)
}

#' Get model configuration for sherpa-onnx C API
#'
#' @param model_info Model info list from resolve_model()
#' @return List with model configuration parameters
#' @keywords internal
get_model_config <- function(model_info) {
  model_type <- model_info$model_type
  model_dir <- model_info$path

  config <- list(
    model_dir = model_dir,
    model_type = model_type
  )

  # Helper to find best file (prefer standard name, then int8, then any match)
  find_model_file <- function(base_name) {
    files <- list.files(model_dir)

    # Try standard name first
    if (base_name %in% files) {
      return(file.path(model_dir, base_name))
    }

    # Try int8 version
    int8_name <- gsub("\\.onnx$", ".int8.onnx", base_name)
    if (int8_name %in% files) {
      return(file.path(model_dir, int8_name))
    }

    # Try pattern match
    pattern <- gsub("\\.onnx$", ".*\\.onnx$", base_name)
    matches <- grep(pattern, files, value = TRUE)
    if (length(matches) > 0) {
      # Prefer non-int8 if multiple matches
      non_int8 <- matches[!grepl("int8", matches)]
      if (length(non_int8) > 0) {
        return(file.path(model_dir, non_int8[1]))
      }
      return(file.path(model_dir, matches[1]))
    }

    return(NULL)
  }

  # Model-specific file paths
  if (model_type == "whisper") {
    config$encoder <- find_model_file("encoder.onnx")
    config$decoder <- find_model_file("decoder.onnx")
    config$tokens <- find_model_file("tokens.txt")
  } else if (model_type == "transducer") {
    config$encoder <- find_model_file("encoder.onnx")
    config$decoder <- find_model_file("decoder.onnx")
    config$joiner <- find_model_file("joiner.onnx")
    config$tokens <- find_model_file("tokens.txt")
  } else if (model_type %in% c("paraformer", "sense-voice")) {
    config$model <- find_model_file("model.onnx")
    config$tokens <- find_model_file("tokens.txt")
  }

  return(config)
}
