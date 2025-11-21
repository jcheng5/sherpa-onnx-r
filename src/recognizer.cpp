// C++ wrapper for sherpa-onnx offline recognizer
// Uses cpp11 for R interface

#include <sherpa-onnx/c-api/c-api.h>
#include <cpp11.hpp>
#include <memory>
#include <string>
#include <vector>
#include <cstring>

using namespace cpp11;

// Helper function to create a default config
static SherpaOnnxOfflineRecognizerConfig get_default_config() {
  SherpaOnnxOfflineRecognizerConfig config;
  memset(&config, 0, sizeof(config));

  config.feat_config.sample_rate = 16000;
  config.feat_config.feature_dim = 80;
  config.model_config.num_threads = 1;
  config.model_config.debug = 0;
  config.model_config.provider = "cpu";
  config.decoding_method = "greedy_search";
  config.max_active_paths = 4;

  return config;
}

// Create an offline recognizer
// Returns an external pointer to the recognizer
[[cpp11::register]]
SEXP create_offline_recognizer_(
    std::string model_dir,
    std::string model_type,
    std::string encoder_path,
    std::string decoder_path,
    std::string joiner_path,
    std::string model_path,
    std::string tokens_path,
    int num_threads,
    std::string provider,
    std::string language,
    std::string modeling_unit) {

  // Create config
  SherpaOnnxOfflineRecognizerConfig config = get_default_config();

  config.model_config.num_threads = num_threads;
  config.model_config.provider = provider.c_str();
  config.model_config.tokens = tokens_path.c_str();

  // Set modeling_unit if provided (for transducer models)
  if (!modeling_unit.empty()) {
    config.model_config.modeling_unit = modeling_unit.c_str();
  }

  // Set model-specific paths
  if (model_type == "whisper") {
    config.model_config.whisper.encoder = encoder_path.c_str();
    config.model_config.whisper.decoder = decoder_path.c_str();
    config.model_config.whisper.language = language.c_str();
    config.model_config.whisper.task = "transcribe";
    config.model_config.whisper.tail_paddings = -1;
  } else if (model_type == "transducer") {
    config.model_config.transducer.encoder = encoder_path.c_str();
    config.model_config.transducer.decoder = decoder_path.c_str();
    config.model_config.transducer.joiner = joiner_path.c_str();
  } else if (model_type == "paraformer") {
    config.model_config.paraformer.model = model_path.c_str();
  } else if (model_type == "sense-voice") {
    config.model_config.sense_voice.model = model_path.c_str();
    config.model_config.sense_voice.language = language.c_str();
    config.model_config.sense_voice.use_itn = 1;
  } else {
    stop("Unknown model type: %s", model_type.c_str());
  }

  // Create recognizer
  const SherpaOnnxOfflineRecognizer *recognizer =
      SherpaOnnxCreateOfflineRecognizer(&config);

  if (recognizer == nullptr) {
    stop("Failed to create offline recognizer. Please check your model files.");
  }

  // Create external pointer with finalizer
  external_pointer<const SherpaOnnxOfflineRecognizer> ptr(
      recognizer,
      true,
      [](const SherpaOnnxOfflineRecognizer *ptr) {
        if (ptr != nullptr) {
          SherpaOnnxDestroyOfflineRecognizer(ptr);
        }
      });

  return ptr;
}

// Transcribe a WAV file
// Returns a list with transcription results
[[cpp11::register]]
list transcribe_wav_(SEXP recognizer_xptr, std::string wav_path) {
  // Get recognizer from external pointer
  external_pointer<const SherpaOnnxOfflineRecognizer> recognizer(recognizer_xptr);

  if (recognizer.get() == nullptr) {
    stop("Invalid recognizer pointer");
  }

  // Read WAV file
  const SherpaOnnxWave *wave = SherpaOnnxReadWave(wav_path.c_str());
  if (wave == nullptr) {
    stop("Failed to read WAV file: %s", wav_path.c_str());
  }

  // Create stream
  const SherpaOnnxOfflineStream *stream =
      SherpaOnnxCreateOfflineStream(recognizer.get());

  if (stream == nullptr) {
    SherpaOnnxFreeWave(wave);
    stop("Failed to create offline stream");
  }

  // Accept waveform
  SherpaOnnxAcceptWaveformOffline(
      stream,
      wave->sample_rate,
      wave->samples,
      wave->num_samples);

  // Decode
  SherpaOnnxDecodeOfflineStream(recognizer.get(), stream);

  // Get result
  const SherpaOnnxOfflineRecognizerResult *result =
      SherpaOnnxGetOfflineStreamResult(stream);

  // Convert result to R list
  writable::list out;

  // Text
  out.push_back({"text"_nm = std::string(result->text)});

  // Tokens
  if (result->tokens_arr != nullptr && result->count > 0) {
    writable::strings tokens_vec;
    for (int32_t i = 0; i < result->count; ++i) {
      tokens_vec.push_back(std::string(result->tokens_arr[i]));
    }
    out.push_back({"tokens"_nm = tokens_vec});
  } else {
    out.push_back({"tokens"_nm = R_NilValue});
  }

  // Timestamps
  if (result->timestamps != nullptr && result->count > 0) {
    writable::doubles timestamps_vec;
    for (int32_t i = 0; i < result->count; ++i) {
      timestamps_vec.push_back(result->timestamps[i]);
    }
    out.push_back({"timestamps"_nm = timestamps_vec});
  } else {
    out.push_back({"timestamps"_nm = R_NilValue});
  }

  // Language
  if (result->lang != nullptr && strlen(result->lang) > 0) {
    out.push_back({"language"_nm = std::string(result->lang)});
  } else {
    out.push_back({"language"_nm = R_NilValue});
  }

  // Emotion
  if (result->emotion != nullptr && strlen(result->emotion) > 0) {
    out.push_back({"emotion"_nm = std::string(result->emotion)});
  } else {
    out.push_back({"emotion"_nm = R_NilValue});
  }

  // JSON
  if (result->json != nullptr) {
    out.push_back({"json"_nm = std::string(result->json)});
  } else {
    out.push_back({"json"_nm = R_NilValue});
  }

  // Cleanup
  SherpaOnnxDestroyOfflineRecognizerResult(result);
  SherpaOnnxDestroyOfflineStream(stream);
  SherpaOnnxFreeWave(wave);

  return out;
}

// Destroy a recognizer (explicit cleanup)
[[cpp11::register]]
void destroy_recognizer_(SEXP recognizer_xptr) {
  external_pointer<const SherpaOnnxOfflineRecognizer> recognizer(recognizer_xptr);

  if (recognizer.get() != nullptr) {
    SherpaOnnxDestroyOfflineRecognizer(recognizer.get());
    recognizer.release();
  }
}

// Read a WAV file and return its properties
[[cpp11::register]]
list read_wav_(std::string wav_path) {
  const SherpaOnnxWave *wave = SherpaOnnxReadWave(wav_path.c_str());

  if (wave == nullptr) {
    stop("Failed to read WAV file: %s", wav_path.c_str());
  }

  // Convert samples to R vector
  writable::doubles samples_vec;
  for (int32_t i = 0; i < wave->num_samples; ++i) {
    samples_vec.push_back(wave->samples[i]);
  }

  writable::list out;
  out.push_back({"samples"_nm = samples_vec});
  out.push_back({"sample_rate"_nm = wave->sample_rate});
  out.push_back({"num_samples"_nm = wave->num_samples});

  SherpaOnnxFreeWave(wave);

  return out;
}
