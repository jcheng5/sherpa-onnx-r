# Quick Start Guide

## Installation

```bash
# Run configure to download binaries
./configure

# Install in R
R -e 'devtools::install()'
```

## Basic Usage

```r
library(sherpa.onnx)

# Create recognizer (downloads model automatically)
rec <- OfflineRecognizer$new(model = "whisper-tiny")

# Transcribe audio
result <- rec$transcribe("test.wav")
cat(result$text)
```

## Available Models

```r
available_models()
# [1] "parakeet-v3"  "whisper-tiny" "whisper-base" "sense-voice"
```

## File Structure

```
/
├── DESCRIPTION           # Package metadata
├── NAMESPACE            # Exports
├── LICENSE              # MIT license
├── README.md            # Full documentation
├── NEXT_STEPS.md        # Build/test instructions
├── configure            # Unix binary download
├── configure.win        # Windows binary download
├── cleanup              # Cleanup script
├── R/
│   ├── model.R         # Model management
│   ├── recognizer.R    # R6 class
│   ├── utils.R         # Utilities
│   └── zzz.R           # Package hooks
├── src/
│   ├── Makevars.in     # Build config
│   ├── recognizer.cpp  # C++ wrapper
│   └── cpp11.cpp       # Registration
└── tests/
    └── testthat/       # Tests
```

## Testing

```r
# Run tests
devtools::test()

# Test with included audio
library(sherpa.onnx)
rec <- OfflineRecognizer$new(model = "whisper-tiny")
rec$transcribe("test.wav")
```
