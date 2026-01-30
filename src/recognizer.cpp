// C++ wrapper for sherpa-onnx offline recognizer
// Uses cpp11 for R interface

#include <sherpa-onnx/c-api/c-api.h>
#include <cpp11.hpp>
#include <memory>
#include <string>
#include <vector>
#include <cstring>
#include <fstream>

using namespace cpp11;

// Deleter function for the recognizer pointer
static void delete_recognizer(const SherpaOnnxOfflineRecognizer *ptr) {
  SherpaOnnxDestroyOfflineRecognizer(ptr);
}

// Validate that a file is a valid WAV file
// Returns true if valid, false otherwise
static bool is_valid_wav(const std::string &filename) {
  std::ifstream file(filename, std::ios::binary);
  if (!file.is_open()) {
    return false;
  }

  // Read RIFF header (first 12 bytes)
  char header[12];
  file.read(header, 12);
  if (!file) {
    return false;
  }

  // Check for "RIFF" magic bytes (0x52494646)
  if (header[0] != 'R' || header[1] != 'I' ||
      header[2] != 'F' || header[3] != 'F') {
    return false;
  }

  // Check for "WAVE" format (0x57415645)
  if (header[8] != 'W' || header[9] != 'A' ||
      header[10] != 'V' || header[11] != 'E') {
    return false;
  }

  return true;
}

// Helper function to convert recognition result to R list
static writable::list convert_result_to_list(const SherpaOnnxOfflineRecognizerResult *result) {
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

  // Durations
  if (result->durations != nullptr && result->count > 0) {
    writable::doubles durations_vec;
    for (int32_t i = 0; i < result->count; ++i) {
      durations_vec.push_back(result->durations[i]);
    }
    out.push_back({"durations"_nm = durations_vec});
  } else {
    out.push_back({"durations"_nm = R_NilValue});
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

  // Event
  if (result->event != nullptr && strlen(result->event) > 0) {
    out.push_back({"event"_nm = std::string(result->event)});
  } else {
    out.push_back({"event"_nm = R_NilValue});
  }

  // JSON
  if (result->json != nullptr) {
    out.push_back({"json"_nm = std::string(result->json)});
  } else {
    out.push_back({"json"_nm = R_NilValue});
  }

  return out;
}

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
      delete_recognizer);

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

  // Validate WAV file format before processing
  if (!is_valid_wav(wav_path)) {
    stop("Invalid WAV file: %s\nOnly standard WAV files (16-bit PCM, mono/stereo) are supported.\nFile must have RIFF/WAVE headers.", wav_path.c_str());
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

  // Convert result to R list using helper
  writable::list out = convert_result_to_list(result);

  // Cleanup
  SherpaOnnxDestroyOfflineRecognizerResult(result);
  SherpaOnnxDestroyOfflineStream(stream);
  SherpaOnnxFreeWave(wave);

  return out;
}

// Transcribe raw audio samples
// Returns a list with transcription results
[[cpp11::register]]
list transcribe_samples_(SEXP recognizer_xptr, doubles samples, int sample_rate) {
  // Get recognizer from external pointer
  external_pointer<const SherpaOnnxOfflineRecognizer> recognizer(recognizer_xptr);

  if (recognizer.get() == nullptr) {
    stop("Invalid recognizer pointer");
  }

  if (samples.size() == 0) {
    stop("Empty audio samples");
  }

  // Convert R doubles to float array
  std::vector<float> samples_vec(samples.size());
  for (size_t i = 0; i < samples.size(); ++i) {
    samples_vec[i] = static_cast<float>(samples[i]);
  }

  // Create stream
  const SherpaOnnxOfflineStream *stream =
      SherpaOnnxCreateOfflineStream(recognizer.get());

  if (stream == nullptr) {
    stop("Failed to create offline stream");
  }

  // Accept waveform
  SherpaOnnxAcceptWaveformOffline(
      stream,
      sample_rate,
      samples_vec.data(),
      samples_vec.size());

  // Decode
  SherpaOnnxDecodeOfflineStream(recognizer.get(), stream);

  // Get result
  const SherpaOnnxOfflineRecognizerResult *result =
      SherpaOnnxGetOfflineStreamResult(stream);

  // Convert result to R list using helper
  writable::list out = convert_result_to_list(result);

  // Cleanup
  SherpaOnnxDestroyOfflineRecognizerResult(result);
  SherpaOnnxDestroyOfflineStream(stream);

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
  // Validate WAV file format before processing
  if (!is_valid_wav(wav_path)) {
    stop("Invalid WAV file: %s\nOnly standard WAV files (16-bit PCM, mono/stereo) are supported.\nFile must have RIFF/WAVE headers.", wav_path.c_str());
  }

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
