# Next Steps to Build and Test the Package

## 1. Build the Package

First, you'll need to run the configure script and build the package:

```bash
# Run configure to download binaries (this may take a few minutes)
./configure

# Check that binaries were downloaded
ls -la inst/libs/
ls -la inst/include/
```

## 2. Install Dependencies

In R, install the required packages:

```r
install.packages(c("R6", "cpp11", "rappdirs", "roxygen2", "devtools", "testthat"))
```

## 3. Generate Documentation

Generate the man pages from roxygen2 comments:

```r
# In R, from the package root directory
devtools::document()
```

## 4. Try Building the Package

Build and install the package:

```bash
# Build package tarball
R CMD build .

# Install with standard R CMD INSTALL
R CMD INSTALL sherpa.onnx_0.1.0.tar.gz

# Or use devtools in R
devtools::install()
```

## 5. Test with the Provided Audio File

Once installed, test with the test.wav file:

```r
library(sherpa.onnx)

# List available models
available_models()

# Create a recognizer (this will download the model on first use)
# Start with whisper-tiny as it's smaller
rec <- OfflineRecognizer$new(model = "whisper-tiny")

# Transcribe the test file
result <- rec$transcribe("test.wav")
cat("Transcription:", result$text, "\n")
```

## 6. Run Tests

Run the test suite:

```r
devtools::test()
```

## 7. Common Issues and Solutions

### Issue: Configure fails to download binaries

**Solution**: Check internet connection and try manually. The configure script downloads architecture-specific binaries:

```bash
# For Apple Silicon (arm64)
curl -L -o sherpa.tar.bz2 https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.17/sherpa-onnx-v1.12.17-osx-arm64-jni.tar.bz2
tar xjf sherpa.tar.bz2

# For Intel (x86_64)
curl -L -o sherpa.tar.bz2 https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.17/sherpa-onnx-v1.12.17-osx-x86_64-jni.tar.bz2
tar xjf sherpa.tar.bz2
```

### Issue: Compilation errors about missing headers

**Solution**: Verify headers were installed:
```bash
ls inst/include/sherpa-onnx/c-api/
```

### Issue: Model download fails

**Solution**: Try downloading manually from HuggingFace:
```r
# Get the cache directory
cache_dir()

# Download model manually to that location
```

### Issue: Runtime library loading errors

**Solution**: Check library paths:
```bash
# On macOS
otool -L inst/libs/libsherpa-onnx-c-api.dylib

# On Linux
ldd inst/libs/libsherpa-onnx-c-api.so
```

## 8. Verify Package Structure

Check that all files are in place:

```bash
# Package structure
tree -L 2 -I 'inst'

# Should show:
# ├── DESCRIPTION
# ├── LICENSE
# ├── NAMESPACE
# ├── README.md
# ├── R/
# ├── cleanup
# ├── configure
# ├── configure.win
# ├── src/
# ├── tests/
# └── man/ (after running devtools::document())
```

## 9. Check Package with R CMD check

For a thorough check:

```bash
R CMD build .
R CMD check sherpa.onnx_0.1.0.tar.gz
```

## 10. Test Different Models

Try different models to ensure they all work:

```r
# Whisper tiny (English)
rec1 <- OfflineRecognizer$new(model = "whisper-tiny")
result1 <- rec1$transcribe("test.wav")

# Whisper base (English, more accurate)
rec2 <- OfflineRecognizer$new(model = "whisper-base")
result2 <- rec2$transcribe("test.wav")

# Parakeet (Paraformer, fast)
rec3 <- OfflineRecognizer$new(model = "parakeet-v3")
result3 <- rec3$transcribe("test.wav")

# Compare results
cat("Whisper tiny:", result1$text, "\n")
cat("Whisper base:", result2$text, "\n")
cat("Parakeet:", result3$text, "\n")
```

## 11. Performance Testing

Test batch processing performance:

```r
# Create multiple copies of test file for testing
file.copy("test.wav", paste0("test_", 1:10, ".wav"))

# Time batch processing
system.time({
  rec <- OfflineRecognizer$new(model = "whisper-tiny")
  results <- rec$transcribe_batch(paste0("test_", 1:10, ".wav"))
})

# Cleanup
file.remove(paste0("test_", 1:10, ".wav"))
```

## 12. Debugging Tips

If you encounter issues:

```r
# Check package load
library(sherpa.onnx, verbose = TRUE)

# Check if C++ library loaded
.Call("_sherpa_onnx_create_offline_recognizer_",
      "", "", "", "", "", "", "", 1L, "cpu", "")

# Enable debugging in C++ (requires recompilation)
# Edit src/recognizer.cpp and set debug = 1 in config

# Check cache
cache_dir()
list.files(cache_dir(), recursive = TRUE)
```

## 13. Contributing Back

Once everything works:

1. Test on different platforms (macOS, Linux, Windows)
2. Add more model shorthands to `SHORTHAND_MODELS` in R/model.R
3. Consider adding streaming/online recognition support
4. Add more examples to README.md
5. Add vignettes for common use cases

## 14. Known Limitations

Current implementation limitations:

1. Only supports offline (non-streaming) recognition
2. No GPU detection or automatic provider selection (defaults to CPU)
3. Limited error messages from C API
4. No support for custom model configurations (beam size, etc.)
5. Windows support needs testing

These could be addressed in future versions.

## 15. Important Notes

### Staged Install Compatibility

The package now uses architecture-specific (thin) binaries instead of universal binaries, which ensures compatibility with R's staged install process. See `notes/STAGED_INSTALL_ISSUE.md` for technical details.

### HuggingFace Integration

Model downloads are handled automatically via the `hfhub` R package, providing reliable model management and caching.
