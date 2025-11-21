# Notes for Claude Code

## Package Status

**STATUS: ✅ FULLY FUNCTIONAL**

The sherpa.onnx R package is successfully implemented and working. It provides offline speech recognition using the sherpa-onnx library with automatic model downloads from HuggingFace Hub.

## Building and Installing

Standard installation works with R's staged install:

```bash
cd ..
R CMD build sherpa-onnx-r
R CMD INSTALL sherpa.onnx_0.1.0.tar.gz
```

**Note**: The package now uses architecture-specific (thin) binaries instead of universal binaries, which resolves previous staged install issues.

## Using the Package

```r
library(sherpa.onnx)

# Create recognizer (downloads model automatically)
rec <- OfflineRecognizer$new(model = "whisper-tiny")

# Transcribe audio
result <- rec$transcribe("test.wav")
cat(result$text)
```

**Available model shorthands**:
- `whisper-tiny` - Whisper tiny model (fast, English-only)
- `whisper-base` - Whisper base model (more accurate, English-only)
- `parakeet-v3` - NeMo Parakeet TDT transducer model (int8 quantized)
- `sense-voice` - Multilingual model (Chinese, English, Japanese, Korean, Cantonese)

Models are cached in: `~/.cache/huggingface/hub/`

**Note**: The package automatically handles int8 quantized models and various file naming conventions.

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
3. **C++ Wrappers**: `R/cpp11_wrappers.R` provides proper `.Call()` interfaces to C++ functions
4. **Model Resolution**: Supports shorthand names, HuggingFace repos, and local paths
5. **Staged Install Compatible**: Uses thin binaries instead of universal binaries to avoid R's staged install bug (see `notes/STAGED_INSTALL_ISSUE.md`)

## Documentation

- Design: `plans/001-INITIAL-DESIGN.md`
- Outcome: `plans/001-INITIAL-DESIGN.outcome.md`
- Usage: `README.md`
- Quick Start: `QUICK_START.md`
- Implementation Summary: `notes/IMPLEMENTATION_SUMMARY.md`
- Next Steps: `notes/NEXT_STEPS.md`
- Staged Install Issue: `notes/STAGED_INSTALL_ISSUE.md` (technical details on universal vs thin binaries)
- Thin Binary Fix: `notes/THIN_BINARY_FIX.md` (solution documentation)
