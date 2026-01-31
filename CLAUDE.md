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
