#' @useDynLib sherpa.onnx, .registration = TRUE
NULL

# Model management functions for sherpa.onnx R package
# Handles model resolution, downloading, and type detection

# Shorthand model mappings
SHORTHAND_MODELS <- list(
  # Parakeet models (NeMo transducer, English)

  "parakeet-v3" = "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
  "parakeet-110m" = "csukuangfj/sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000",

  # Whisper models (English-only)

  "whisper-tiny" = "csukuangfj/sherpa-onnx-whisper-tiny.en",
  "whisper-base" = "csukuangfj/sherpa-onnx-whisper-base.en",
  "whisper-small" = "csukuangfj/sherpa-onnx-whisper-small.en",
  "whisper-medium" = "csukuangfj/sherpa-onnx-whisper-medium.en",

  # Whisper models (Multilingual)
  "whisper-tiny-multilingual" = "csukuangfj/sherpa-onnx-whisper-tiny",
  "whisper-base-multilingual" = "csukuangfj/sherpa-onnx-whisper-base",
  "whisper-medium-multilingual" = "csukuangfj/sherpa-onnx-whisper-medium",

  # Whisper distilled models (English-only, faster)
  "whisper-distil-small" = "csukuangfj/sherpa-onnx-whisper-distil-small.en",
  "whisper-distil-medium" = "csukuangfj/sherpa-onnx-whisper-distil-medium.en",

  # SenseVoice (Multilingual: Chinese, English, Japanese, Korean, Cantonese)
  "sense-voice" = "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17",

  # VAD models
  "silero-vad" = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"
)

#' Download VAD model
#'
#' @param vad_model VAD model name or URL (default: "silero-vad")
#' @param verbose Whether to print progress
#' @return Path to downloaded VAD model
#' @noRd
download_vad_model <- function(vad_model = "silero-vad", verbose = TRUE) {
  cache_dir <- get_cache_dir()
  vad_cache <- file.path(cache_dir, "vad")

  if (!dir.exists(vad_cache)) {
    dir.create(vad_cache, recursive = TRUE)
  }

  # Handle shorthand or URL
  if (vad_model == "silero-vad") {
    url <- SHORTHAND_MODELS[["silero-vad"]]
    local_path <- file.path(vad_cache, "silero_vad.onnx")
  } else if (grepl("^https?://", vad_model)) {
    url <- vad_model
    local_path <- file.path(vad_cache, basename(vad_model))
  } else {
    # Assume it's a local path
    if (file.exists(vad_model)) {
      return(normalizePath(vad_model))
    }
    stop("VAD model not found: ", vad_model)
  }

  # Check if already cached
  if (file.exists(local_path)) {
    if (verbose) message("Using cached VAD model: ", local_path)
    return(normalizePath(local_path, mustWork = TRUE))
  }

  if (verbose) message("Downloading VAD model from: ", url)

  # Download
  tryCatch({
    download.file(url, local_path, mode = "wb", quiet = !verbose)
    if (verbose) message("VAD model downloaded to: ", local_path)
    return(normalizePath(local_path, mustWork = TRUE))
  }, error = function(e) {
    stop("Failed to download VAD model: ", e$message)
  })
}

#' Resolve model specification to local path
#'
#' @param model Model specification (shorthand, HF repo, or local path)
#' @param verbose Logical, whether to print messages
#' @return List with type, path, and model_type
#' @noRd
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
  shorthand <- NULL
  if (grepl("/", model, fixed = TRUE)) {
    hf_repo <- model
  } else {
    # 3. Treat as shorthand
    shorthand <- model
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

  result <- list(
    type = "huggingface",
    repo = hf_repo,
    path = model_path,
    model_type = detect_model_type(model_path)
  )

  # Store shorthand name for display purposes
  if (!is.null(shorthand)) {
    result$shorthand <- shorthand
  }

  return(result)
}

#' Download model from HuggingFace Hub
#'
#' @param repo HuggingFace repository (e.g., "csukuangfj/sherpa-onnx-whisper-tiny.en")
#' @param verbose Logical, whether to print messages
#' @return Local path to downloaded model
#' @noRd
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

  return(model_path)
}

#' Guess model filenames from directory
#'
#' Takes a model directory and returns a named list mapping standard names
#' (encoder, decoder, joiner, tokens, model) to actual filenames found.
#' Handles custom naming like "tiny.en-encoder.onnx" or "encoder.int8.onnx".
#'
#' @param model_dir Path to model directory
#' @return Named list with actual filenames, or NULL for missing files
#' @noRd
guess_model_files <- function(model_dir) {
  files <- list.files(model_dir)

  # Helper to find best candidate for a given pattern
  # Prefer non-int8 versions if available
  find_best_file <- function(pattern) {
    candidates <- grep(pattern, files, value = TRUE)
    if (length(candidates) == 0) return(NULL)

    # Prefer non-int8 versions
    non_int8 <- candidates[!grepl("int8", candidates)]
    if (length(non_int8) > 0) {
      return(non_int8[1])
    }

    return(candidates[1])
  }

  list(
    encoder = find_best_file("encoder.*\\.onnx$"),
    decoder = find_best_file("decoder.*\\.onnx$"),
    joiner = find_best_file("joiner.*\\.onnx$"),
    tokens = find_best_file("tokens\\.txt$"),
    model = find_best_file("^model.*\\.onnx$")
  )
}

#' Detect model type from files in directory
#'
#' @param model_dir Path to model directory
#' @return String indicating model type
#' @noRd
detect_model_type <- function(model_dir) {
  model_files <- guess_model_files(model_dir)

  # Check for transducer (encoder + decoder + joiner)
  if (!is.null(model_files$encoder) &&
      !is.null(model_files$decoder) &&
      !is.null(model_files$joiner)) {
    return("transducer")
  }

  # Check for whisper (encoder + decoder, no joiner)
  if (!is.null(model_files$encoder) && !is.null(model_files$decoder)) {
    return("whisper")
  }

  # Check for paraformer or sense-voice (single model.onnx)
  if (!is.null(model_files$model)) {
    # Check for sense-voice indicators
    if (any(grepl("sense-?voice", model_dir, ignore.case = TRUE)) ||
        any(grepl("sense-?voice", model_files$model, ignore.case = TRUE))) {
      return("sense-voice")
    } else {
      return("paraformer")
    }
  }

  files <- list.files(model_dir)
  stop(
    "Could not detect model type from files in: ", model_dir,
    "\nFiles found: ", paste(files, collapse = ", ")
  )
}

#' Get cache directory for models
#'
#' @return Path to cache directory
#' @noRd
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
#' @noRd
get_model_config <- function(model_info) {
  model_type <- model_info$model_type
  model_dir <- model_info$path

  config <- list(
    model_dir = model_dir,
    model_type = model_type
  )

  # Get guessed filenames from directory
  model_files <- guess_model_files(model_dir)

  # Model-specific file paths (use full paths)
  if (model_type == "whisper") {
    config$encoder <- if (!is.null(model_files$encoder)) file.path(model_dir, model_files$encoder)
    config$decoder <- if (!is.null(model_files$decoder)) file.path(model_dir, model_files$decoder)
    config$tokens <- if (!is.null(model_files$tokens)) file.path(model_dir, model_files$tokens)
  } else if (model_type == "transducer") {
    config$encoder <- if (!is.null(model_files$encoder)) file.path(model_dir, model_files$encoder)
    config$decoder <- if (!is.null(model_files$decoder)) file.path(model_dir, model_files$decoder)
    config$joiner <- if (!is.null(model_files$joiner)) file.path(model_dir, model_files$joiner)
    config$tokens <- if (!is.null(model_files$tokens)) file.path(model_dir, model_files$tokens)
  } else if (model_type %in% c("paraformer", "sense-voice")) {
    config$model <- if (!is.null(model_files$model)) file.path(model_dir, model_files$model)
    config$tokens <- if (!is.null(model_files$tokens)) file.path(model_dir, model_files$tokens)
  }

  return(config)
}
