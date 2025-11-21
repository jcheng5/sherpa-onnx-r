# Wrapper functions for C++ code
# These functions provide the R interface to the C++ functions

#' @keywords internal
create_offline_recognizer_ <- function(model_dir, model_type, encoder_path,
                                       decoder_path, joiner_path, model_path,
                                       tokens_path, num_threads, provider, language,
                                       modeling_unit) {
  .Call(
    "_sherpa_onnx_create_offline_recognizer_",
    model_dir, model_type, encoder_path, decoder_path, joiner_path,
    model_path, tokens_path, num_threads, provider, language, modeling_unit,
    PACKAGE = "sherpa.onnx"
  )
}

#' @keywords internal
transcribe_wav_ <- function(recognizer_xptr, wav_path) {
  .Call(
    "_sherpa_onnx_transcribe_wav_",
    recognizer_xptr, wav_path,
    PACKAGE = "sherpa.onnx"
  )
}

#' @keywords internal
destroy_recognizer_ <- function(recognizer_xptr) {
  .Call(
    "_sherpa_onnx_destroy_recognizer_",
    recognizer_xptr,
    PACKAGE = "sherpa.onnx"
  )
}

#' @keywords internal
read_wav_ <- function(wav_path) {
  .Call(
    "_sherpa_onnx_read_wav_",
    wav_path,
    PACKAGE = "sherpa.onnx"
  )
}
