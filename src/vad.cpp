// C++ wrapper for sherpa-onnx Voice Activity Detection (VAD)
// Uses cpp11 for R interface

#include <sherpa-onnx/c-api/c-api.h>
#include <cpp11.hpp>
#include <memory>
#include <string>
#include <vector>
#include <cstring>

using namespace cpp11;

// Extract VAD segments from audio samples
// Returns a list of segments, each with samples, start_time, and duration
[[cpp11::register]]
list extract_vad_segments_(
    std::string vad_model_path,
    doubles samples,
    int sample_rate,
    double vad_threshold,
    double vad_min_silence,
    double vad_min_speech,
    double vad_max_speech,
    int vad_window_size,
    bool verbose) {

  if (samples.size() == 0) {
    stop("Empty audio samples");
  }

  // Convert R doubles to float array
  std::vector<float> samples_vec(samples.size());
  for (size_t i = 0; i < samples.size(); ++i) {
    samples_vec[i] = static_cast<float>(samples[i]);
  }

  // Create VAD configuration
  SherpaOnnxVadModelConfig vad_config;
  memset(&vad_config, 0, sizeof(vad_config));

  // Configure Silero VAD
  vad_config.silero_vad.model = vad_model_path.c_str();
  vad_config.silero_vad.threshold = static_cast<float>(vad_threshold);
  vad_config.silero_vad.min_silence_duration = static_cast<float>(vad_min_silence);
  vad_config.silero_vad.min_speech_duration = static_cast<float>(vad_min_speech);
  vad_config.silero_vad.max_speech_duration = static_cast<float>(vad_max_speech);
  vad_config.silero_vad.window_size = vad_window_size;

  vad_config.sample_rate = sample_rate;
  vad_config.num_threads = 1;
  vad_config.debug = verbose ? 1 : 0;

  // Create VAD instance (buffer size = 60 seconds to handle batching)
  const SherpaOnnxVoiceActivityDetector *vad =
      SherpaOnnxCreateVoiceActivityDetector(&vad_config, 60.0f);

  if (vad == nullptr) {
    stop("Failed to create VAD instance. Check model path: %s", vad_model_path.c_str());
  }

  // Collect all VAD segments
  writable::list segments_list;
  size_t i = 0;
  int is_eof = 0;
  int num_segments = 0;

  while (!is_eof) {
    // Feed audio to VAD in windows
    if (i + vad_window_size < samples_vec.size()) {
      SherpaOnnxVoiceActivityDetectorAcceptWaveform(
          vad, samples_vec.data() + i, vad_window_size);
    } else {
      // Last chunk - flush VAD
      SherpaOnnxVoiceActivityDetectorFlush(vad);
      is_eof = 1;
    }

    // Collect all available speech segments
    while (!SherpaOnnxVoiceActivityDetectorEmpty(vad)) {
      const SherpaOnnxSpeechSegment *segment =
          SherpaOnnxVoiceActivityDetectorFront(vad);

      // Convert samples to R doubles
      writable::doubles seg_samples;
      for (int32_t j = 0; j < segment->n; ++j) {
        seg_samples.push_back(segment->samples[j]);
      }

      // Calculate times
      double start_time = segment->start / static_cast<double>(sample_rate);
      double duration = segment->n / static_cast<double>(sample_rate);

      // Create segment list
      writable::list seg_info;
      seg_info.push_back({"samples"_nm = seg_samples});
      seg_info.push_back({"start_time"_nm = start_time});
      seg_info.push_back({"duration"_nm = duration});

      segments_list.push_back(seg_info);
      num_segments++;

      SherpaOnnxDestroySpeechSegment(segment);
      SherpaOnnxVoiceActivityDetectorPop(vad);
    }

    i += vad_window_size;
  }

  // Cleanup VAD
  SherpaOnnxDestroyVoiceActivityDetector(vad);

  if (verbose) {
    Rprintf("VAD detected %d speech segments\n", num_segments);
  }

  // Return result
  writable::list out;
  out.push_back({"segments"_nm = segments_list});
  out.push_back({"num_segments"_nm = num_segments});

  return out;
}

