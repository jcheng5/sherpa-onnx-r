# sherpa.onnx

> Offline Speech Recognition for R

An R package that provides offline speech recognition (audio file to text transcription) using the [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) library. Features automatic model downloads from HuggingFace Hub, support for multiple model architectures (Whisper, Paraformer, SenseVoice), and efficient batch processing.

## UNDER CONSTRUCTION

- There are currently limitations with regard to audio length. Keep audio input under 30 seconds for reliable transcription. (See [#1](https://github.com/jcheng5/sherpa-onnx-r/issues/1))

## Features

- **Offline transcription**: No internet required after model download
- **Multiple model architectures**: Whisper, Paraformer, SenseVoice, Transducer
- **Automatic model management**: Downloads models from HuggingFace Hub
- **Simple API**: R6 class interface with sensible defaults
- **Batch processing**: Transcribe multiple files efficiently
- **Cross-platform**: Works on macOS, Linux (x64 only), and Windows (x64 only)

## Installation

```r
pak::pak("jcheng5/sherpa-onnx-r")
```

**Note**: The package downloads OS- and architecture-specific binaries (31-34 MB) during installation.

### Using system sherpa-onnx

If you have sherpa-onnx installed on your system, you can try forcing sherpa.onnx to use it (this has not been well tested):

```r
withr::with_envvar(list(SHERPA_ONNX_USE_SYSTEM="1"),
  remotes::install_github("jcheng5/sherpa-onnx-r")
)
```

## Quick Start

```r
library(sherpa.onnx)

# Create a recognizer (downloads model on first use)
rec <- OfflineRecognizer$new(model = "whisper-tiny")

# Transcribe a single file
result <- rec$transcribe("audio.wav")
cat(result$text)
#> "This is a test audio file"

# Transcribe multiple files
results <- rec$transcribe_batch(c("file1.wav", "file2.wav"))
```

## Usage

### Creating a Recognizer

There are three ways to specify a model:

```r
# 1. Use a shorthand for popular models (easiest)
rec <- OfflineRecognizer$new(model = "whisper-tiny")

# 2. Use a full HuggingFace repository path
rec <- OfflineRecognizer$new(
  model = "csukuangfj/sherpa-onnx-whisper-tiny.en"
)

# 3. Use a local directory path
rec <- OfflineRecognizer$new(model = "/path/to/model-directory")
```

### Available Models

View all available shorthand models:

```r
available_models()
#> [1] "parakeet-v3" "parakeet-110m" "whisper-tiny" "whisper-base" ...
```

#### Parakeet Models (NeMo Transducer, English)

| Shorthand | HuggingFace Repo | Size | Speed | Notes |
|-----------|------------------|------|-------|-------|
| `parakeet-v3` | `csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` | 671 MB | 0.9s | Production default, best balance |
| `parakeet-110m` | `csukuangfj/sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000` | 478 MB | 0.15s | 6x faster, edge devices |

#### Whisper Models (English-only)

| Shorthand | HuggingFace Repo | Size | Speed | Notes |
|-----------|------------------|------|-------|-------|
| `whisper-tiny` | `csukuangfj/sherpa-onnx-whisper-tiny.en` | 257 MB | 0.3s | Fastest, good accuracy |
| `whisper-base` | `csukuangfj/sherpa-onnx-whisper-base.en` | ~500 MB | 0.5s | Balanced |
| `whisper-small` | `csukuangfj/sherpa-onnx-whisper-small.en` | 1.34 GB | 1.8s | Better accuracy |
| `whisper-medium` | `csukuangfj/sherpa-onnx-whisper-medium.en` | ~3 GB | 5.8s | High accuracy |

#### Whisper Models (Multilingual)

| Shorthand | HuggingFace Repo | Speed | Notes |
|-----------|------------------|-------|-------|
| `whisper-tiny-multilingual` | `csukuangfj/sherpa-onnx-whisper-tiny` | 0.3s | 99 languages, fastest |
| `whisper-base-multilingual` | `csukuangfj/sherpa-onnx-whisper-base` | 0.5s | 99 languages |
| `whisper-medium-multilingual` | `csukuangfj/sherpa-onnx-whisper-medium` | 5.9s | 99 languages, better accuracy |

#### Whisper Distilled Models (English-only, faster)

| Shorthand | HuggingFace Repo | Speed | Notes |
|-----------|------------------|-------|-------|
| `whisper-distil-small` | `csukuangfj/sherpa-onnx-whisper-distil-small.en` | 1.15s | Faster than small, similar accuracy |
| `whisper-distil-medium` | `csukuangfj/sherpa-onnx-whisper-distil-medium.en` | 2.7s | Faster than medium, similar accuracy |

#### SenseVoice (Multilingual with Special Features)

| Shorthand | HuggingFace Repo | Speed | Notes |
|-----------|------------------|-------|-------|
| `sense-voice` | `csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17` | 0.34s | **Unique features:** Emotion detection, audio event detection, language tags |

**Languages:** Chinese, English, Japanese, Korean, Cantonese

**Special capabilities:**
- Returns emotion tags: `<|NEUTRAL|>`, `<|HAPPY|>`, `<|SAD|>`, etc.
- Returns language tags: `<|en|>`, `<|zh|>`, `<|ja|>`, etc.
- Detects audio events: applause, laughter, music
- Excellent for code-switching (mixed languages)

**Speed benchmarks** are for ~13 second audio on Apple M-series (varies by hardware). Multilingual Whisper models require `language = "en"` parameter.

### Transcribing Audio

```r
# Single file
result <- rec$transcribe("speech.wav")

# Access different parts of the result
result$text        # Transcribed text
result$tokens      # Token sequence
result$timestamps  # Token timestamps (if supported)
result$language    # Detected language (if supported)
result$json        # Full result as JSON
```

### Batch Transcription

```r
# Transcribe multiple files
wav_files <- c("lecture1.wav", "lecture2.wav", "lecture3.wav")
results <- rec$transcribe_batch(wav_files)

# Process results
for (i in seq_along(results)) {
  cat(sprintf("File %d: %s\n", i, results[[i]]$text))
}
```

### Model Information

```r
# Get information about the loaded model
info <- rec$model_info()
info$model_type  # "whisper", "paraformer", etc.
info$path        # Local path to model files
```

### Advanced Options

```r
# Create recognizer with custom settings
rec <- OfflineRecognizer$new(
  model = "whisper-base",
  language = "en",      # Language hint for multilingual models
  num_threads = 4,      # Number of CPU threads
  provider = "cpu"      # or "cuda", "coreml"
)
```

## Audio Requirements

Input audio files must be:
- Format: WAV (PCM)
- Sample rate: 16 kHz (recommended, will be resampled if different)
- Channels: Mono (single channel)
- Bit depth: 16-bit

To convert audio files, you can use `ffmpeg`:

```bash
# Convert any audio file to the required format
ffmpeg -i input.m4a -ar 16000 -ac 1 -c:a pcm_s16le output.wav
```

## Model Cache

Models are cached locally after download:

```r
# Get cache directory path
cache_dir()

# Clear cache (with confirmation)
clear_cache()

# Set custom cache directory (before loading models)
Sys.setenv(SHERPA_ONNX_CACHE_DIR = "/custom/cache/path")
```

## Model Recommendations

### By Use Case

**General production use (English):**
- `parakeet-v3` - Best overall balance of speed, accuracy, and size

**Speed priority (English):**
- `parakeet-110m` - 6x faster than parakeet-v3, great for edge devices
- `whisper-tiny` - Fast Whisper variant

**Accuracy priority (English):**
- `whisper-medium` - Highest tested accuracy
- `whisper-small` - Good balance of accuracy and speed

**Multilingual:**
- `sense-voice` - Best for Chinese/Japanese/Korean/Cantonese + emotion detection
- `whisper-medium-multilingual` - 99 languages supported

**Special features:**
- `sense-voice` - Only model with emotion detection and audio event classification

**Edge devices / Low memory:**
- `parakeet-110m` - Only 478 MB, very fast
- `whisper-tiny` - Only 257 MB

### Model Architectures

The package supports three main architectures:

1. **NeMo Transducer (Parakeet)**: State-of-the-art English models from NVIDIA
2. **Whisper**: OpenAI's robust models with excellent punctuation and capitalization
3. **SenseVoice**: Multilingual model with emotion detection capabilities

## Examples

### Basic Transcription

```r
library(sherpa.onnx)

rec <- OfflineRecognizer$new(model = "whisper-tiny")
result <- rec$transcribe("test.wav")
cat(result$text)
```

### Multilingual Transcription with Emotion Detection

```r
# SenseVoice provides emotion and language detection
rec <- OfflineRecognizer$new(model = "sense-voice")
result <- rec$transcribe("audio.wav")

cat("Text:", result$text, "\n")
cat("Language:", result$language, "\n")      # e.g., "<|en|>"
cat("Emotion:", result$emotion, "\n")        # e.g., "<|NEUTRAL|>"
# Also detects: <|HAPPY|>, <|SAD|>, <|ANGRY|>, events like <|APPLAUSE|>
```

### Batch Processing

```r
# Get all WAV files in a directory
wav_files <- list.files("audio/", pattern = "\\.wav$", full.names = TRUE)

# Transcribe all files
rec <- OfflineRecognizer$new(model = "whisper-base")
results <- rec$transcribe_batch(wav_files)

# Save results to a data frame
library(dplyr)
transcriptions <- data.frame(
  file = basename(wav_files),
  text = sapply(results, function(x) x$text),
  stringsAsFactors = FALSE
)
```

## Performance Tips

1. **Choose the right model size**: Smaller models (tiny, base) are faster but less accurate
2. **Use multiple threads**: Set `num_threads` to match your CPU cores
3. **Batch processing**: Use `transcribe_batch()` for multiple files
4. **GPU acceleration**: Use `provider = "cuda"` if you have CUDA available

## Troubleshooting

### Installation Issues

If you encounter issues during installation:

```r
# Check if binaries were downloaded
list.files(system.file("libs", package = "sherpa.onnx"))

# Verify architecture matches your system
system("uname -m")  # Should be arm64 or x86_64 on macOS

# Try using system sherpa-onnx
Sys.setenv(SHERPA_ONNX_USE_SYSTEM = "1")
install.packages("sherpa.onnx", type = "source")
```

For technical details about the binary architecture and R's staged install process, see `notes/STAGED_INSTALL_ISSUE.md` and `notes/THIN_BINARY_FIX.md` in the package source.

### Model Download Issues

If model downloads fail:

```r
# Try downloading manually
model_info <- resolve_model("whisper-tiny")
model_info$path  # Check where model should be

# Clear cache and retry
clear_cache(confirm = FALSE)
```

### Audio Format Issues

If you get errors about audio format:

```r
# Check audio properties
audio_info <- read_wav("audio.wav")
audio_info$sample_rate  # Should be 16000
audio_info$num_samples  # Total samples
```

## License

MIT License

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Citation

If you use this package in your research, please cite:

```
sherpa-onnx: https://github.com/k2-fsa/sherpa-onnx
```

## Related Projects

- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) - The underlying C++ library
- [audio.whisper](https://github.com/bnosac/audio.whisper) - R wrapper around [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
