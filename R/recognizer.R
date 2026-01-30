# Batch VAD segments together up to a maximum duration
# Each batch will contain concatenated audio from one or more segments
# @param segments List of segments from extract_vad_segments_()
# @param max_duration Maximum batch duration in seconds (default 29 for Whisper)
# @return List of batches, each with samples, start_time, and duration
batch_segments <- function(segments, max_duration = 29.0) {
  if (length(segments) == 0) {
    return(list())
  }

  batches <- list()
  batch_idx <- 1
  seg_idx <- 1

  while (seg_idx <= length(segments)) {
    batch_samples <- numeric(0)
    batch_start_time <- segments[[seg_idx]]$start_time
    batch_duration <- 0.0

    while (seg_idx <= length(segments)) {
      seg <- segments[[seg_idx]]

      # Always add at least one segment; stop if exceeding max
      if (length(batch_samples) > 0 &&
          (batch_duration + seg$duration) > max_duration) {
        break
      }

      batch_samples <- c(batch_samples, seg$samples)
      batch_duration <- batch_duration + seg$duration
      seg_idx <- seg_idx + 1
    }

    batches[[batch_idx]] <- list(
      samples = batch_samples,
      start_time = batch_start_time,
      duration = batch_duration
    )
    batch_idx <- batch_idx + 1
  }

  batches
}

#' Offline Speech Recognizer
#'
#' @description
#' R6 class for offline speech recognition using sherpa-onnx.
#' Supports multiple model architectures including Whisper, Paraformer,
#' SenseVoice, and Transducer models.
#'
#' @importFrom R6 R6Class
#' @importFrom utils download.file head
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
    # Uses vad() for speech detection, then transcribes each batch
    transcribe_with_vad = function(wav_path, vad_config) {
      # Run VAD to detect speech segments
      vad_result <- vad(
        wav_path,
        threshold = vad_config$threshold,
        min_silence = vad_config$min_silence,
        min_speech = vad_config$min_speech,
        max_speech = vad_config$max_speech,
        model = vad_config$model,
        verbose = vad_config$verbose
      )

      # Handle case of no speech detected
      if (vad_result$num_segments == 0) {
        result <- list(
          text = "",
          segments = character(0),
          segment_starts = numeric(0),
          segment_durations = numeric(0),
          num_segments = 0L
        )
        return(new_sherpa_transcription(result, private$model_info_cache))
      }

      # Batch segments (R) - groups segments up to 29s max
      batches <- batch_segments(vad_result$segments, max_duration = 29.0)

      # Transcribe each batch (C++)
      batch_results <- lapply(seq_along(batches), function(i) {
        batch <- batches[[i]]

        if (vad_config$verbose) {
          message(sprintf("Transcribing batch %d: %.2f - %.2f sec",
                          i, batch$start_time, batch$start_time + batch$duration))
        }

        transcription <- transcribe_samples_(
          private$recognizer_ptr,
          batch$samples,
          vad_result$sample_rate
        )

        list(
          text = transcription$text,
          start_time = batch$start_time,
          duration = batch$duration
        )
      })

      # Combine results (R)
      segment_texts <- vapply(batch_results, function(x) x$text, character(1))
      segment_starts <- vapply(batch_results, function(x) x$start_time, numeric(1))
      segment_durations <- vapply(batch_results, function(x) x$duration, numeric(1))

      # Combine text, skipping empty segments
      non_empty <- nzchar(trimws(segment_texts))
      full_text <- trimws(paste(segment_texts[non_empty], collapse = " "))

      result <- list(
        text = full_text,
        segments = segment_texts,
        segment_starts = segment_starts,
        segment_durations = segment_durations,
        num_segments = length(batch_results)
      )

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
    #' @param verbose Logical. Show progress messages. Default: TRUE
    #'
    #' @return A sherpa_transcription object (list-like) containing:
    #'   - text: Transcribed text
    #'   - tokens: Character vector of tokens
    #'   - timestamps: Numeric vector of timestamps (if supported by model)
    #'   - durations: Numeric vector of token durations (if supported by model)
    #'   - language: Detected language (if supported by model)
    #'   - emotion: Detected emotion (if supported by model)
    #'   - event: Detected audio event (if supported by model)
    #'   - json: Full result as JSON string
    #'
    #'   For Whisper models with audio longer than 29 seconds, Voice Activity

    #'   Detection (VAD) is automatically used to segment the audio. In this case,
    #'   additional fields are available:
    #'   - segments: Character vector of segment texts
    #'   - segment_starts: Start times of segments in seconds
    #'   - segment_durations: Duration of segments in seconds
    #'   - num_segments: Number of segments
    #'
    #'   The result has a custom print method but maintains list-like access
    #'   (e.g., `result$text`). Use `as.character(result)` to extract just the
    #'   text, or `summary(result)` for detailed statistics.
    #'
    #' @details
    #' Whisper models have a 30-second context window limit. For audio longer than
    #' 29 seconds, this method automatically uses Voice Activity Detection (VAD)
    #' to split the audio at natural speech boundaries, transcribes each segment,
    #' and combines the results. This happens transparently - you don't need to
    #' configure anything.
    #'
    #' For other model types (Parakeet, SenseVoice, etc.), the entire audio is
    #' transcribed at once regardless of length.
    #'
    #' If you need fine-grained control over VAD parameters, use the standalone
    #' `vad()` function to detect speech segments, then transcribe them individually.
    #'
    #' @examples
    #' \dontrun{
    #' rec <- OfflineRecognizer$new(model = "whisper-tiny")
    #' result <- rec$transcribe("audio.wav")
    #'
    #' # Print with custom format
    #' print(result)
    #'
    #' # Access fields
    #' cat("Transcription:", result$text, "\n")
    #'
    #' # Extract text
    #' text <- as.character(result)
    #'
    #' # Detailed information
    #' summary(result)
    #' }
    transcribe = function(wav_path, verbose = TRUE) {
      # Expand tilde and other path shortcuts
      wav_path <- path.expand(wav_path)

      if (!file.exists(wav_path)) {
        stop("WAV file not found: ", wav_path)
      }

      if (is.null(private$recognizer_ptr)) {
        stop("Recognizer not initialized")
      }

      # Check if we need VAD (whisper model + audio > 29s)
      use_vad <- FALSE
      model_type <- private$model_info_cache$model_type

      if (model_type == "whisper") {
        # Read audio to check duration
        wav_data <- read_wav_(wav_path)
        duration <- wav_data$num_samples / wav_data$sample_rate

        if (duration > 29.0) {
          use_vad <- TRUE
          if (verbose) {
            message(sprintf("Audio is %.1f seconds; using VAD for Whisper model", duration))
          }
        }
      }

      # Simple transcription (no VAD needed)
      if (!use_vad) {
        result <- transcribe_wav_(private$recognizer_ptr, wav_path)
        return(new_sherpa_transcription(result, private$model_info_cache))
      }

      # VAD-based transcription with defaults
      vad_config <- list(
        model = "silero-vad",
        threshold = 0.5,
        min_silence = 0.5,
        min_speech = 0.25,
        max_speech = 29.0,
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
