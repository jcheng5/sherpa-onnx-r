# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Package Status

**STATUS: ✅ FULLY FUNCTIONAL**

The sherpa.onnx R package is successfully implemented and working. It provides offline speech recognition using the sherpa-onnx library with automatic model downloads from HuggingFace Hub.

## Development Workflow

### Building and Installing

Standard installation works with R's staged install:

```bash
cd ..
R CMD build sherpa-onnx-r
R CMD INSTALL sherpa.onnx_0.1.0.tar.gz
```

Or from within R during development:

```r
devtools::load_all()     # Load package for testing
devtools::document()     # Update documentation
devtools::install()      # Install package
```

**Note**: The package uses architecture-specific (thin) binaries instead of universal binaries, which resolves previous staged install issues.

### Running Tests

```r
# Run all tests (fast, uses whisper-tiny only)
devtools::test()

# Run comprehensive model tests (downloads ~3-4 GB, takes 10-30 minutes)
Sys.setenv(SHERPA_TEST_ALL_MODELS = "true")
devtools::test()

# Run specific test file
devtools::test_file("tests/testthat/test-recognizer.R")
```

From command line:

```bash
# Standard R CMD check
R CMD check sherpa.onnx_*.tar.gz

# With comprehensive model tests
SHERPA_TEST_ALL_MODELS=true R CMD check sherpa.onnx_*.tar.gz
```

**Test environment variables:**
- `SHERPA_TEST_ALL_MODELS=true` - Run comprehensive model tests (9 Whisper + 2 Parakeet)
- `SHERPA_BENCHMARK=true` - Run performance benchmarks and generate CSVs

## Code Architecture

### High-Level Structure

The package consists of three main layers:

1. **C++ Layer** (`src/`): C++ wrapper around sherpa-onnx C API
   - `recognizer.cpp` - Main recognition interface
   - `vad.cpp` - Voice Activity Detection
   - `cpp11.cpp` - cpp11 bindings (auto-generated)

2. **R Layer** (`R/`): R6 classes and utilities
   - `recognizer.R` - `OfflineRecognizer` R6 class (main user interface)
   - `model.R` - Model resolution, download, and configuration
   - `vad.R` - VAD wrapper functions
   - `transcription.R` - Result formatting and tibble output
   - `utils.R` - Cache management, helper functions
   - `cpp11.R` - cpp11 interface definitions (auto-generated)

3. **Binary Management** (`configure`, `configure.win`): Shell scripts that download platform-specific sherpa-onnx binaries during installation

### Key Design Patterns

**Model Resolution**: Three-tier model specification system:
- Shorthand names (`"whisper-tiny.en"`) → mapped in `SHORTHAND_MODELS` list
- HuggingFace repos (`"csukuangfj/sherpa-onnx-whisper-tiny.en"`) → downloaded via `hfhub::hub_snapshot()`
- Local paths (`"/path/to/model"`) → used directly

**Quantization Support**: Suffix notation for quantized models:
- Format: `"model-name:quantization"` (e.g., `"whisper-base.en:int8"`)
- Handled in `resolve_model()` function
- Automatically falls back to non-quantized version if unavailable

**VAD-based Processing**: Long audio files are automatically chunked:
- VAD detects speech segments
- Segments are batched (up to 29 seconds for Whisper)
- Each batch is transcribed separately
- Results are concatenated with timing information

**Memory Management**:
- C++ objects wrapped in R6 classes with finalizers
- External pointers automatically cleaned up via `private$finalize()`
- Models cached in `~/.cache/huggingface/hub/`

### File Purposes

**Core R files:**
- `R/recognizer.R` - Main API, `OfflineRecognizer` class with `transcribe()` and `transcribe_batch()` methods
- `R/model.R` - `resolve_model()`, `detect_model_type()`, model shorthand mappings
- `R/vad.R` - `vad()` function for speech detection, segment extraction
- `R/transcription.R` - `new_sherpa_transcription()` for result formatting

**Core C++ files:**
- `src/recognizer.cpp` - `create_recognizer_()`, `transcribe_()`, direct calls to sherpa-onnx C API
- `src/vad.cpp` - `vad_()` wrapper around sherpa-onnx VAD

**Configuration:**
- `configure` - Unix/macOS binary download script (bash)
- `configure.win` - Windows binary download script (cmd/batch)
- `src/Makevars.in` - Template for Unix build configuration
- `src/Makevars.win.in` - Template for Windows build configuration

### CUDA Support

CUDA is auto-detected during installation on Linux/Windows:
- `configure` checks for `nvidia-smi` availability
- Downloads CUDA-enabled binaries (~350 MB) if GPU detected
- Falls back to CPU-only binaries (~20 MB) otherwise
- CUDA binaries support both CPU and GPU inference via `provider` parameter

**Environment variables:**
- `SHERPA_ONNX_CUDA=1` - Force CUDA binaries
- `SHERPA_ONNX_CUDA=0` - Force CPU-only binaries
- `SHERPA_ONNX_CUDA` unset - Auto-detect (checks for nvidia-smi)
- `SHERPA_ONNX_CUDA_VERSION=cuda-11|cuda-12` - Select CUDA version (default: cuda-12)
- `SHERPA_ONNX_USE_SYSTEM=1` - Use system-installed sherpa-onnx

## Using the Package

```r
library(sherpa.onnx)

# Create recognizer (downloads model automatically)
rec <- OfflineRecognizer$new(model = "whisper-tiny.en")

# Use int8 quantized version (smaller size)
rec <- OfflineRecognizer$new(model = "whisper-tiny.en:int8")

# Transcribe audio
result <- rec$transcribe("test.wav")
cat(result$text)
```

**Available model shorthands** (complete list from sherpa-onnx):

Parakeet (NeMo, English):
- `parakeet-v3` - 600M model, production default (671 MB)
- `parakeet-110m` - Smaller/faster model (478 MB)

Whisper (English-only, `.en` suffix):
- `whisper-tiny.en` - Fastest (~75 MB)
- `whisper-base.en` - Balanced (~140 MB)
- `whisper-small.en` - Better accuracy (~465 MB)
- `whisper-medium.en` - High accuracy (~1.5 GB)

Whisper (Multilingual, 99 languages):
- `whisper-tiny` - Fastest multilingual (~75 MB)
- `whisper-base` - Balanced (~140 MB)
- `whisper-small` - Better accuracy (~465 MB)
- `whisper-medium` - High accuracy (~1.5 GB)
- `whisper-large` - Best accuracy, alias for v3 (~3 GB)
- `whisper-large-v1` - Large v1 (~3 GB)
- `whisper-large-v2` - Large v2 (~3 GB)
- `whisper-large-v3` - Large v3, latest (~3 GB)
- `whisper-turbo` - 8x faster than large (~800 MB)
- `whisper-medium.en-aishell1` - Chinese Mandarin fine-tuned (~1.5 GB)

Whisper Distilled (English-only, faster):
- `whisper-distil-small.en` - Faster than small.en
- `whisper-distil-medium.en` - Faster than medium.en

Whisper Distilled (Multilingual, faster):
- `whisper-distil-large-v2` - Faster than large-v2
- `whisper-distil-large-v3` - Faster than large-v3
- `whisper-distil-large-v3.5` - Latest distilled, fastest large variant

SenseVoice (Special Features):
- `sense-voice` - Multilingual with emotion detection
  - Languages: Chinese, English, Japanese, Korean, Cantonese
  - Returns emotion tags: `<|NEUTRAL|>`, `<|HAPPY|>`, `<|SAD|>`, etc.
  - Returns language tags: `<|en|>`, `<|zh|>`, `<|ja|>`, etc.
  - Detects audio events: applause, laughter, music

Models are cached in: `~/.cache/huggingface/hub/`

**Total: 26 models** (2 Parakeet, 19 Whisper variants, 5 distilled, 1 SenseVoice)

**Quantized Models**: Add `:int8` (or `:fp16`, etc.) suffix to any model to prefer quantized versions:
- Example: `whisper-base.en:int8` (smaller size, minimal accuracy loss)
- Benefits: 2-4x smaller file size, reduced memory usage
- Performance: May be faster OR slower depending on hardware/backend - benchmark both versions
- The package automatically handles quantized models and various file naming conventions
- If no quantized version exists, falls back to regular version automatically

## sherpa-onnx Source Location

The sherpa-onnx C++ library source code may or may not be located at:
```
../../k2-fsa/sherpa-onnx
```

This includes:
- C API headers: `sherpa-onnx/c-api/c-api.h`
- C API examples: `c-api-examples/*.c`
- Build artifacts: `build/`

## Test Audio File

A test audio file is available for testing transcription:
```
test.wav
```

Properties:
- Format: PCM 16-bit WAV
- Sample rate: 16000 Hz
- Channels: Mono (1 channel)
- Duration: ~13 seconds
- Original source: test.m4a (converted with ffmpeg)
- **Known transcription**: "Posit's mission is to create open source software for data science, scientific research, and technical communication. We do this to enhance the production and consumption of knowledge by everyone regardless of economic means."

## Key Implementation Details

1. **hfhub Integration**: Uses `hfhub::hub_snapshot()` for reliable model downloads
2. **Binary Management**: Architecture-specific (thin) binaries (~31-34MB) download during installation via `configure` script from sherpa-onnx JNI builds
3. **C++ Bindings**: Uses cpp11 package for R-to-C++ interface (`R/cpp11.R`, `src/cpp11.cpp`)
4. **Model Resolution**: Supports shorthand names, HuggingFace repos, and local paths with automatic quantization handling
5. **Staged Install Compatible**: Uses thin binaries instead of universal binaries to avoid R's staged install bug (see `notes/STAGED_INSTALL_ISSUE.md`)

## Documentation

- Design: `plans/001-INITIAL-DESIGN.md`
- Outcome: `plans/001-INITIAL-DESIGN.outcome.md`
- VAD Chunking: `plans/003-VAD-CHUNKING.md`
- Usage: `README.md`
- Quick Start: `QUICK_START.md`
- Implementation Summary: `notes/IMPLEMENTATION_SUMMARY.md`
- Next Steps: `notes/NEXT_STEPS.md`
- Staged Install Issue: `notes/STAGED_INSTALL_ISSUE.md` (technical details on universal vs thin binaries)
- Thin Binary Fix: `notes/THIN_BINARY_FIX.md` (solution documentation)
- Testing: `tests/README.md` (comprehensive testing guide)

## Common Development Tasks

### Adding a New Model Shorthand

1. Add to `SHORTHAND_MODELS` list in `R/model.R`
2. Update `README.md` model tables
3. Update this file's model list
4. Test with `OfflineRecognizer$new(model = "new-model-name")`

### Modifying C++ Code

After changing C++ files:

```r
devtools::clean_dll()    # Clean compiled objects
devtools::load_all()     # Recompile and load
```

Or use R CMD SHLIB:

```bash
R CMD SHLIB src/*.cpp -I/path/to/sherpa-onnx/include
```

### Updating cpp11 Bindings

If you modify C++ function signatures exported to R:

```r
cpp11::cpp_register()    # Regenerate R/cpp11.R and src/cpp11.cpp
devtools::document()     # Update documentation
```

### Debugging

Enable verbose output for model downloads and transcription:

```r
rec <- OfflineRecognizer$new(model = "whisper-tiny.en", verbose = TRUE)
result <- rec$transcribe("test.wav", verbose = TRUE)
```

Check sherpa-onnx library loading:

```r
.dynLibs()               # List loaded dynamic libraries
dyn.load(system.file("libs", "sherpa.onnx.so", package = "sherpa.onnx"))
```

### Performance Testing

Use the standalone test scripts:

```bash
Rscript test_whisper_models.R    # Test 9 Whisper models
Rscript test_parakeet_models.R   # Test 2 Parakeet models
```

These generate CSV files with timing comparisons.

## Troubleshooting

### Binary Download Issues

If configure fails to download binaries:

```bash
# Check platform detection
uname -s    # Darwin (macOS) or Linux
uname -m    # arm64, x86_64

# Manually download and extract
SHERPA_VERSION="v1.12.17"
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_VERSION}/sherpa-onnx-${SHERPA_VERSION}-osx-arm64-jni.tar.bz2
tar -xjf sherpa-onnx-${SHERPA_VERSION}-osx-arm64-jni.tar.bz2
cp sherpa-onnx-${SHERPA_VERSION}-osx-arm64-jni/lib/*.dylib inst/libs/
```

### R CMD check Issues

If staged install fails, ensure you're using thin binaries (not universal):

```bash
# Check library architecture on macOS
lipo -info inst/libs/libsherpa-onnx-c-api.dylib
# Should show single architecture, not "universal"
```

### Model Loading Errors

Some models with external `.weights` files may fail (upstream sherpa-onnx issue):
- whisper-large-v2, whisper-large-v3, whisper-distil-large-v3
- Use int8 quantized versions instead (e.g., `"whisper-large-v3:int8"`)

### Cache Issues

Clear model cache if downloads are corrupted:

```r
clear_cache(confirm = FALSE)
# Or manually:
unlink("~/.cache/huggingface/hub", recursive = TRUE)
```
