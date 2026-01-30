// C++ wrapper for sherpa-onnx Voice Activity Detection (VAD)
// Uses cpp11 for R interface

#include <sherpa-onnx/c-api/c-api.h>
#include <cpp11.hpp>
#include <memory>
#include <string>
#include <vector>
#include <cstring>

using namespace cpp11;

// Maximum batch duration in seconds (Whisper truncates at 30s, use 29s for safety margin)
static const float MAX_BATCH_DURATION = 29.0f;

// Structure to hold a VAD segment's data
struct VadSegment {
  std::vector<float> samples;
  int32_t start_sample;  // Start position in original audio
  int32_t num_samples;   // Number of samples
};

// Transcribe audio using VAD segmentation
// VAD segments are batched together up to 30 seconds to preserve context
[[cpp11::register]]
list transcribe_with_vad_(
    SEXP recognizer_xptr,
    std::string vad_model_path,
    doubles samples,
    int sample_rate,
    double vad_threshold,
    double vad_min_silence,
    double vad_min_speech,
    double vad_max_speech,
    int vad_window_size,
    bool verbose) {

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

  // First pass: collect all VAD segments
  std::vector<VadSegment> vad_segments;
  size_t i = 0;
  int is_eof = 0;

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

      VadSegment vs;
      vs.start_sample = segment->start;
      vs.num_samples = segment->n;
      vs.samples.assign(segment->samples, segment->samples + segment->n);

      vad_segments.push_back(std::move(vs));

      SherpaOnnxDestroySpeechSegment(segment);
      SherpaOnnxVoiceActivityDetectorPop(vad);
    }

    i += vad_window_size;
  }

  // Cleanup VAD
  SherpaOnnxDestroyVoiceActivityDetector(vad);

  if (verbose) {
    Rprintf("VAD detected %zu speech segments\n", vad_segments.size());
  }

  // Storage for transcription results (one per batch)
  std::vector<std::string> batch_texts;
  std::vector<double> batch_start_times;
  std::vector<double> batch_durations;

  // Second pass: batch segments together up to MAX_BATCH_DURATION and transcribe
  size_t seg_idx = 0;
  int batch_count = 0;

  while (seg_idx < vad_segments.size()) {
    // Start a new batch
    std::vector<float> batch_samples;
    int32_t batch_start_sample = vad_segments[seg_idx].start_sample;
    float batch_duration = 0.0f;

    // Add segments to batch until we would exceed MAX_BATCH_DURATION
    while (seg_idx < vad_segments.size()) {
      const VadSegment& seg = vad_segments[seg_idx];
      float seg_duration = seg.num_samples / static_cast<float>(sample_rate);

      // Check if adding this segment would exceed the limit
      // Always add at least one segment to the batch
      if (!batch_samples.empty() && (batch_duration + seg_duration) > MAX_BATCH_DURATION) {
        break;
      }

      // Add this segment's samples to the batch
      batch_samples.insert(batch_samples.end(), seg.samples.begin(), seg.samples.end());
      batch_duration += seg_duration;
      seg_idx++;
    }

    batch_count++;
    float batch_start_sec = batch_start_sample / static_cast<float>(sample_rate);

    if (verbose) {
      Rprintf("Transcribing batch %d: %.2f - %.2f sec (%.2f sec, %zu samples)\n",
              batch_count, batch_start_sec, batch_start_sec + batch_duration,
              batch_duration, batch_samples.size());
    }

    // Transcribe this batch
    const SherpaOnnxOfflineStream *stream =
        SherpaOnnxCreateOfflineStream(recognizer.get());

    SherpaOnnxAcceptWaveformOffline(
        stream, sample_rate, batch_samples.data(), batch_samples.size());

    SherpaOnnxDecodeOfflineStream(recognizer.get(), stream);

    const SherpaOnnxOfflineRecognizerResult *result =
        SherpaOnnxGetOfflineStreamResult(stream);

    // Store batch info
    batch_start_times.push_back(static_cast<double>(batch_start_sec));
    batch_durations.push_back(static_cast<double>(batch_duration));
    batch_texts.push_back(std::string(result->text));

    // Cleanup
    SherpaOnnxDestroyOfflineRecognizerResult(result);
    SherpaOnnxDestroyOfflineStream(stream);
  }

  // Build combined result
  std::string full_text;
  for (size_t j = 0; j < batch_texts.size(); ++j) {
    std::string seg_text = batch_texts[j];

    // Skip empty segments
    if (seg_text.empty()) continue;

    // Add space between non-empty segments
    if (!full_text.empty()) {
      full_text += " ";
    }
    full_text += seg_text;
  }

  // Convert vectors to R types
  writable::strings segments_vec;
  writable::doubles starts_vec;
  writable::doubles durations_vec;

  for (size_t j = 0; j < batch_texts.size(); ++j) {
    segments_vec.push_back(batch_texts[j]);
    starts_vec.push_back(batch_start_times[j]);
    durations_vec.push_back(batch_durations[j]);
  }

  writable::list out;
  out.push_back({"text"_nm = full_text});
  out.push_back({"segments"_nm = segments_vec});
  out.push_back({"segment_starts"_nm = starts_vec});
  out.push_back({"segment_durations"_nm = durations_vec});
  out.push_back({"num_segments"_nm = batch_count});

  return out;
}
