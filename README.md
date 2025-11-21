# sherpa.onnx

> Offline Speech Recognition for R

An R package that provides offline speech recognition (audio file to text transcription) using the [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) library. Features automatic model downloads from HuggingFace Hub, support for multiple model architectures (Whisper, Paraformer, SenseVoice), and efficient batch processing.

## Features

- **Offline transcription**: No internet required after model download
- **Multiple model architectures**: Whisper, Paraformer, SenseVoice, Transducer
- **Automatic model management**: Downloads models from HuggingFace Hub
- **Simple API**: R6 class interface with sensible defaults
- **Batch processing**: Transcribe multiple files efficiently
- **Cross-platform**: Works on macOS, Linux, and Windows

## Installation

### From source

```r
# Install dependencies
install.packages(c("R6", "cpp11", "rappdirs", "hfhub"))

# Install sherpa.onnx
# The configure script will automatically download pre-built binaries
install.packages("sherpa.onnx", type = "source")
```

**Note**: The package downloads architecture-specific binaries (31-34 MB) during installation. On macOS, separate binaries are provided for Apple Silicon (arm64) and Intel (x86_64) processors.

### Using system sherpa-onnx

If you have sherpa-onnx installed on your system, you can use it instead:

```bash
export SHERPA_ONNX_USE_SYSTEM=1
R CMD INSTALL sherpa.onnx
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

### Available Shorthand Models

```r
available_models()
#> [1] "parakeet-v3"  "whisper-tiny" "whisper-base" "sense-voice"
```

- **parakeet-v3**: Paraformer model for English (default)
- **whisper-tiny**: Whisper tiny model for English
- **whisper-base**: Whisper base model for English
- **sense-voice**: Multilingual model (Chinese, English, Japanese, Korean, Cantonese)

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

## Supported Models

The package supports various model architectures:

1. **Whisper**: OpenAI's Whisper models
   - Best for English transcription
   - Multiple sizes: tiny, base, small, medium

2. **Paraformer**: Alibaba's Paraformer models
   - Fast and accurate
   - Good for English

3. **SenseVoice**: Multilingual models
   - Supports multiple languages and emotions
   - Good for Chinese, English, Japanese, Korean

4. **Transducer**: Streaming-capable models
   - RNN-T architecture
   - Good for real-time applications

## Examples

### Basic Transcription

```r
library(sherpa.onnx)

rec <- OfflineRecognizer$new(model = "whisper-tiny")
result <- rec$transcribe("test.wav")
cat(result$text)
```

### Multilingual Transcription

```r
rec <- OfflineRecognizer$new(model = "sense-voice")
result <- rec$transcribe("chinese_audio.wav")
cat("Detected language:", result$language, "\n")
cat("Text:", result$text, "\n")
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
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - Alternative Whisper implementation
- [vosk](https://alphacephei.com/vosk/) - Another offline speech recognition toolkit
