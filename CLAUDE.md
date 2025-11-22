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

**Available model shorthands** (all tested and working):

Parakeet (NeMo, English):
- `parakeet-v3` - 600M model, production default (671 MB, 0.9s)
- `parakeet-110m` - Smaller/faster model (478 MB, 0.15s)

Whisper (English-only):
- `whisper-tiny` - Fastest (257 MB, 0.3s)
- `whisper-base` - Balanced (500 MB, 0.5s)
- `whisper-small` - Better accuracy (1.34 GB, 1.8s)
- `whisper-medium` - High accuracy (3 GB, 5.8s)

Whisper (Multilingual, 99 languages):
- `whisper-tiny-multilingual` - Fastest multilingual
- `whisper-base-multilingual` - Balanced multilingual
- `whisper-medium-multilingual` - Best accuracy multilingual

Whisper Distilled (English-only, faster):
- `whisper-distil-small` - Faster than small
- `whisper-distil-medium` - Faster than medium

SenseVoice (Special Features):
- `sense-voice` - Multilingual with emotion detection (0.34s)
  - Languages: Chinese, English, Japanese, Korean, Cantonese
  - Returns emotion tags: `<|NEUTRAL|>`, `<|HAPPY|>`, `<|SAD|>`, etc.
  - Returns language tags: `<|en|>`, `<|zh|>`, `<|ja|>`, etc.
  - Detects audio events: applause, laughter, music

Models are cached in: `~/.cache/huggingface/hub/`

**Speed benchmarks** are for ~13 second audio on Apple M-series.

**Tested and verified:** All models above have been tested and confirmed working.

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
