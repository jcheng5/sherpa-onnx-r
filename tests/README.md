# Testing sherpa.onnx

This directory contains tests for the sherpa.onnx R package.

## Test Structure

- `testthat/test-model.R` - Model resolution and configuration tests
- `testthat/test-recognizer.R` - Basic recognizer functionality tests
- `testthat/test-model-comparison.R` - Model comparison and performance tests

## Running Tests

### Default Tests (Fast, CI-friendly)

Run all default tests including basic whisper-tiny model test:

```r
devtools::test()
```

Or with R CMD check:

```bash
R CMD check sherpa.onnx_*.tar.gz
```

**Default behavior:**
- Runs whisper-tiny model test
- Skips comprehensive model comparisons
- Suitable for CI/CD pipelines

### Comprehensive Model Tests

Test all available models (downloads ~3-4 GB, takes 10-30 minutes):

```r
Sys.setenv(SHERPA_TEST_ALL_MODELS = "true")
devtools::test()
```

Or from command line:

```bash
SHERPA_TEST_ALL_MODELS=true R CMD check sherpa.onnx_*.tar.gz
```

**Comprehensive tests:**
- Tests 9 Whisper models (tiny, base, small, medium variants)
- Tests 2 Parakeet models (v3-int8, 110m)
- Verifies transcription accuracy
- Measures performance differences
- Takes 10-30 minutes depending on download speeds

### Performance Benchmarks

Run full performance benchmarks and generate comparison CSVs:

```r
Sys.setenv(SHERPA_BENCHMARK = "true")
devtools::test()
```

This will:
- Run `test_whisper_models.R` script
- Run `test_parakeet_models.R` script
- Generate `whisper_model_comparison.csv`
- Generate `parakeet_model_comparison.csv`

## Test Files in Root Directory

Two standalone test scripts are available in the root directory:

### test_whisper_models.R

Tests 9 Whisper models and generates a comparison report:

```bash
Rscript test_whisper_models.R
```

**Output:**
- `whisper_model_comparison.csv` - Detailed results table
- Console output with speed comparisons and analysis

**Models tested:**
- whisper-tiny.en, base.en, small.en, medium.en
- whisper-tiny, base, medium (multilingual)
- whisper-distil-small.en, distil-medium.en

### test_parakeet_models.R

Tests 2 Parakeet models and generates a comparison report:

```bash
Rscript test_parakeet_models.R
```

**Output:**
- `parakeet_model_comparison.csv` - Detailed results table
- Console output with speed comparison (110m vs 600m)

**Models tested:**
- parakeet-v3-int8 (600M, production default)
- parakeet-110m (faster, smaller)

## CI/CD Configuration

### GitHub Actions Example

```yaml
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v2
    - uses: r-lib/actions/setup-r@v2
    - name: Install dependencies
      run: |
        install.packages("devtools")
        devtools::install_deps()
    - name: Run default tests
      run: devtools::test()
      # Only runs whisper-tiny, skips comprehensive tests
```

To run comprehensive tests in CI (not recommended due to time/bandwidth):

```yaml
    - name: Run comprehensive tests
      run: devtools::test()
      env:
        SHERPA_TEST_ALL_MODELS: true
```

## Test Data

Tests use `test.wav` located in `inst/extdata/`:
- **Duration:** ~13 seconds
- **Format:** 16kHz, 16-bit, mono WAV
- **Content:** Posit mission statement
- **Access**: Via `system.file("extdata", "test.wav", package = "sherpa.onnx")`

This file is installed with the package and available for both testing and user examples.

## Known Limitations

Some models are currently disabled in tests due to sherpa-onnx limitations:

### External Weights Issue

Models with external `.weights` files fail to load:
- whisper-large-v2, whisper-large-v3
- whisper-distil-large-v3
- parakeet-v3 (float32)

**Status:** Waiting for [sherpa-onnx PR #2807](https://github.com/k2-fsa/sherpa-onnx/pull/2807) to be merged.

### Metadata Issue

The CTC model crashes with missing metadata:
- parakeet-110m-ctc

**Status:** Under investigation.

## Troubleshooting

### Tests fail with "test.wav not available"

The test audio file should be in `inst/extdata/test.wav`. If tests fail:

```bash
# Verify file exists
ls inst/extdata/test.wav

# Run tests from package root
Rscript -e "devtools::test()"
```

The test scripts automatically find the audio file using `system.file()` for installed packages or fall back to the development path.

### Download failures

Model downloads may fail due to network issues. If this happens:
1. Check internet connection
2. Clear HuggingFace cache: `rm -rf ~/.cache/huggingface/hub`
3. Retry the test

### Out of memory errors

Large models may require significant RAM:
- whisper-medium: ~4 GB RAM
- parakeet-v3: ~3 GB RAM

Consider testing fewer models or increasing available memory.

## Development

When adding new models:

1. Add to appropriate test script (`test_whisper_models.R` or `test_parakeet_models.R`)
2. Add to comprehensive tests in `test-model-comparison.R`
3. Document any known issues in this README
4. Keep default tests fast (whisper-tiny only)

## Performance Expectations

Typical transcription times for 13-second audio on M-series Mac:

| Model | Size | Time | Use Case |
|-------|------|------|----------|
| whisper-tiny.en | 257 MB | ~0.3s | Fast, English-only |
| whisper-base.en | ~500 MB | ~0.5s | Balanced |
| whisper-small.en | 1.34 GB | ~1.8s | Better accuracy |
| whisper-medium.en | ~3 GB | ~5.8s | High accuracy |
| parakeet-110m | 478 MB | ~0.15s | Speed optimized |
| parakeet-v3-int8 | 671 MB | ~0.9s | Production default |

Times may vary significantly on different hardware.
