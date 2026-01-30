#' Offline Speech Recognizer
#'
#' @description
#' R6 class for offline speech recognition using sherpa-onnx.
#' Supports multiple model architectures including Whisper, Paraformer,
#' SenseVoice, and Transducer models.
#'
#' @importFrom R6 R6Class
#' @export
OfflineRecognizer <- R6::R6Class(
  "OfflineRecognizer",

  private = list(
    recognizer_ptr = NULL,
    model_info_cache = NULL,

    # Cleanup resources (called automatically on garbage collection)
    finalize = function() {
      if (!is.null(private$recognizer_ptr)) {
        # The external pointer has a finalizer that will call
        # SherpaOnnxDestroyOfflineRecognizer automatically
        private$recognizer_ptr <- NULL
      }
    },

    # Private method for VAD-based transcription
    transcribe_with_vad = function(wav_path, vad_config) {
      # Load audio
      wav_data <- read_wav_(wav_path)
      samples <- wav_data$samples
      sample_rate <- wav_data$sample_rate

      # Ensure VAD model is available
      vad_model_path <- download_vad_model(
        vad_config$model,
        verbose = vad_config$verbose
      )

      # Call C++ VAD transcription
      result <- transcribe_with_vad_(
        private$recognizer_ptr,
        vad_model_path,
        samples,
        sample_rate,
        vad_config$threshold,
        vad_config$min_silence,
        vad_config$min_speech,
        vad_config$max_speech,
        vad_config$window_size,
        vad_config$verbose
      )

      # Create transcription object with segment info
      new_sherpa_transcription(result, private$model_info_cache)
    }
  ),

  public = list(
    #' @description
    #' Create a new offline recognizer
    #'
    #' @param model Model specification. Can be:
    #'   - A shorthand string: "parakeet-v3", "whisper-tiny", "whisper-base", "sense-voice"
    #'   - A HuggingFace repository: "csukuangfj/sherpa-onnx-whisper-tiny.en"
    #'   - A local directory path containing model files
    #' @param language Language code for multilingual models (default: "auto").
    #'   Used for Whisper and SenseVoice models.
    #' @param num_threads Number of threads for inference (default: NULL = auto-detect).
    #'   If NULL, uses parallel::detectCores() with a maximum of 4 threads.
    #' @param provider Execution provider: "cpu", "cuda", or "coreml" (default: "cpu")
    #' @param verbose Logical, whether to print status messages (default: TRUE)
    #'
    #' @return A new OfflineRecognizer object
    #'
    #' @examples
    #' \dontrun{
    #' # Create recognizer with shorthand (auto-detects threads)
    #' rec <- OfflineRecognizer$new(model = "whisper-tiny")
    #'
    #' # Create recognizer with specific thread count
    #' rec <- OfflineRecognizer$new(model = "whisper-tiny", num_threads = 4)
    #'
    #' # Create recognizer with HuggingFace repo
    #' rec <- OfflineRecognizer$new(
    #'   model = "csukuangfj/sherpa-onnx-whisper-tiny.en"
    #' )
    #'
    #' # Create recognizer with local model
    #' rec <- OfflineRecognizer$new(model = "/path/to/model")
    #' }
    initialize = function(model = "parakeet-v3",
                         language = "auto",
                         num_threads = NULL,
                         provider = "cpu",
                         verbose = TRUE) {

      # Auto-detect optimal thread count if not specified
      if (is.null(num_threads)) {
        available_cores <- parallel::detectCores(logical = FALSE)
        # Use up to 4 threads by default (diminishing returns beyond this)
        num_threads <- min(available_cores, 4)
        if (verbose) {
          message(sprintf("Auto-detected %d physical cores, using %d threads",
                         available_cores, num_threads))
        }
      }

      # Resolve model
      model_info <- resolve_model(model, verbose = verbose)
      private$model_info_cache <- model_info

      # Get model configuration
      config <- get_model_config(model_info)

      # Prepare paths for C++ function
      encoder_path <- if (!is.null(config$encoder)) config$encoder else ""
      decoder_path <- if (!is.null(config$decoder)) config$decoder else ""
      joiner_path <- if (!is.null(config$joiner)) config$joiner else ""
      model_path <- if (!is.null(config$model)) config$model else ""
      tokens_path <- config$tokens

      # Set modeling_unit for transducer models
      # "cjkchar" is needed for NeMo Parakeet and other CJK models
      modeling_unit <- if (config$model_type == "transducer") "cjkchar" else ""

      # Create recognizer via C++ wrapper
      if (verbose) message("Creating recognizer...")
      private$recognizer_ptr <- create_offline_recognizer_(
        model_dir = config$model_dir,
        model_type = config$model_type,
        encoder_path = encoder_path,
        decoder_path = decoder_path,
        joiner_path = joiner_path,
        model_path = model_path,
        tokens_path = tokens_path,
        num_threads = as.integer(num_threads),
        provider = provider,
        language = language,
        modeling_unit = modeling_unit
      )

      if (verbose) message("Recognizer created successfully")
    },

    #' @description
    #' Transcribe a WAV file
    #'
    #' @param wav_path Path to WAV file (must be 16kHz, 16-bit, mono)
    #' @param use_vad Logical. If TRUE, uses Voice Activity Detection to split
    #'   long audio files at natural pauses. Recommended for files longer than
    #'   30 seconds. Default: FALSE (transcribe entire file at once).
    #' @param vad_threshold Speech detection threshold (0-1). Lower = more sensitive.
    #'   Default: 0.5
    #' @param vad_min_silence Minimum silence duration (seconds) to split segments.
    #'   Default: 0.5
    #' @param vad_min_speech Minimum speech duration (seconds) to keep segment.
    #'   Default: 0.25
    #' @param vad_max_speech Maximum speech duration (seconds) before force split.
    #'   Default: 30.0. Useful to prevent memory issues with very long speech.
    #' @param vad_model VAD model to use. Default: "silero-vad" (auto-downloaded)
    #' @param verbose Logical. Show progress messages. Default: TRUE
    #'
    #' @return A sherpa_transcription object (list-like) containing:
    #'   - text: Transcribed text
    #'   - tokens: Character vector of tokens (if not using VAD)
    #'   - timestamps: Numeric vector of timestamps (if supported by model)
    #'   - durations: Numeric vector of token durations (if supported by model)
    #'   - language: Detected language (if supported by model)
    #'   - emotion: Detected emotion (if supported by model)
    #'   - event: Detected audio event (if supported by model)
    #'   - json: Full result as JSON string (if not using VAD)
    #'   - segments: Character vector of segment texts (if VAD used)
    #'   - segment_starts: Start times of segments in seconds (if VAD used)
    #'   - segment_durations: Duration of segments in seconds (if VAD used)
    #'   - num_segments: Number of segments (if VAD used)
    #'
    #'   The result has a custom print method but maintains list-like access
    #'   (e.g., `result$text`). Use `as.character(result)` to extract just the
    #'   text, or `summary(result)` for detailed statistics.
    #'
    #' @examples
    #' \dontrun{
    #' rec <- OfflineRecognizer$new(model = "whisper-tiny")
    #' result <- rec$transcribe("audio.wav")
    #'
    #' # Print with custom format
    #' print(result)
    #'
    #' # Access fields (backward compatible)
    #' cat("Transcription:", result$text, "\n")
    #'
    #' # Extract text
    #' text <- as.character(result)
    #'
    #' # Detailed information
    #' summary(result)
    #'
    #' # Long audio with VAD
    #' result <- rec$transcribe("podcast.wav", use_vad = TRUE)
    #' print(result)  # Shows full text
    #' result$segments  # Individual speech segments
    #' result$segment_starts  # Timing of each segment
    #' }
    transcribe = function(wav_path,
                         use_vad = FALSE,
                         vad_threshold = 0.5,
                         vad_min_silence = 0.5,
                         vad_min_speech = 0.25,
                         vad_max_speech = 29.0,
                         vad_model = "silero-vad",
                         verbose = TRUE) {
      # Expand tilde and other path shortcuts
      wav_path <- path.expand(wav_path)

      if (!file.exists(wav_path)) {
        stop("WAV file not found: ", wav_path)
      }

      if (is.null(private$recognizer_ptr)) {
        stop("Recognizer not initialized")
      }

      # Validate VAD parameters
      if (use_vad) {
        if (vad_threshold < 0 || vad_threshold > 1) {
          stop("vad_threshold must be between 0 and 1")
        }
        if (vad_min_silence < 0) {
          stop("vad_min_silence must be non-negative")
        }
        if (vad_min_speech < 0) {
          stop("vad_min_speech must be non-negative")
        }
        if (vad_max_speech <= 0) {
          stop("vad_max_speech must be positive")
        }
      }

      # Simple transcription (no VAD)
      if (!use_vad) {
        result <- transcribe_wav_(private$recognizer_ptr, wav_path)
        return(new_sherpa_transcription(result, private$model_info_cache))
      }

      # VAD-based transcription
      vad_config <- list(
        model = vad_model,
        threshold = vad_threshold,
        min_silence = vad_min_silence,
        min_speech = vad_min_speech,
        max_speech = vad_max_speech,
        window_size = 512L,  # Silero VAD window size
        verbose = verbose
      )

      private$transcribe_with_vad(wav_path, vad_config)
    },

    #' @description
    #' Transcribe multiple WAV files in batch
    #'
    #' @param wav_paths Character vector of WAV file paths
    #'
    #' @return Tibble with one row per file and columns:
    #'   - file: Input file path (character)
    #'   - text: Transcribed text (character)
    #'   - tokens: List-column of token character vectors
    #'   - timestamps: List-column of timestamp numeric vectors (or NULL)
    #'   - durations: List-column of duration numeric vectors (or NULL)
    #'   - language: Detected language (character, NA if not available)
    #'   - emotion: Detected emotion (character, NA if not available)
    #'   - event: Detected audio event (character, NA if not available)
    #'   - json: Full result as JSON string (character)
    #'
    #' @examples
    #' \dontrun{
    #' rec <- OfflineRecognizer$new(model = "whisper-tiny")
    #' results <- rec$transcribe_batch(c("file1.wav", "file2.wav"))
    #'
    #' # Access results via tibble columns
    #' print(results$text)
    #' print(results$file[1])
    #'
    #' # Access list-columns
    #' first_tokens <- results$tokens[[1]]
    #' }
    transcribe_batch = function(wav_paths) {
      if (length(wav_paths) == 0) {
        # Return empty tibble with correct column structure
        return(tibble::tibble(
          file = character(0),
          text = character(0),
          tokens = list(),
          timestamps = list(),
          durations = list(),
          language = character(0),
          emotion = character(0),
          event = character(0),
          json = character(0)
        ))
      }

      # Transcribe all files
      results <- lapply(wav_paths, function(path) {
        self$transcribe(path)
      })

      # Convert list of results to tibble
      tibble::tibble(
        file = wav_paths,
        text = vapply(results, function(r) r$text, character(1)),
        tokens = lapply(results, function(r) r$tokens),
        timestamps = lapply(results, function(r) r$timestamps),
        durations = lapply(results, function(r) r$durations),
        language = vapply(results, function(r) {
          if (is.null(r$language)) NA_character_ else r$language
        }, character(1)),
        emotion = vapply(results, function(r) {
          if (is.null(r$emotion)) NA_character_ else r$emotion
        }, character(1)),
        event = vapply(results, function(r) {
          if (is.null(r$event)) NA_character_ else r$event
        }, character(1)),
        json = vapply(results, function(r) r$json, character(1))
      )
    },

    #' @description
    #' Get model information
    #'
    #' @return List with model metadata including:
    #'   - type: "local" or "huggingface"
    #'   - path: Local path to model files
    #'   - model_type: Type of model (whisper, paraformer, sense-voice, transducer)
    #'   - repo: HuggingFace repository (if applicable)
    #'
    #' @examples
    #' \dontrun{
    #' rec <- OfflineRecognizer$new(model = "whisper-tiny")
    #' info <- rec$model_info()
    #' print(info)
    #' }
    model_info = function() {
      private$model_info_cache
    }
  )
)
