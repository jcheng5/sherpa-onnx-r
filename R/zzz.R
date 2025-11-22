# Package hooks and initialization

#' @useDynLib sherpa.onnx, .registration = TRUE
.onLoad <- function(libname, pkgname) {
  # Nothing needed here for now
  # The C++ library is loaded automatically via useDynLib in NAMESPACE
}

.onAttach <- function(libname, pkgname) {
  packageStartupMessage(
    "sherpa.onnx: Offline Speech Recognition\n",
    "Version: ", utils::packageVersion("sherpa.onnx"), "\n",
    "Use OfflineRecognizer$new() to get started.\n",
    "Available models: ", paste(available_models(), collapse = ", ")
  )
}

.onUnload <- function(libpath) {
  library.dynam.unload("sherpa.onnx", libpath)
}
