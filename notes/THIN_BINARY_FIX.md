# Thin Binary Fix - Summary

**Date**: 2025-11-21
**Status**: ✅ **RESOLVED**

## Problem

R's staged install was failing with the error:
```
ERROR: some hard-coded temporary paths could not be fixed
```

This was caused by using **universal (fat) binaries** that contain both x86_64 and arm64 architectures. R's `patch_rpaths()` function has a bug where it only removes the first architecture header from `otool -l` output, leaving the second header with the temporary installation path.

See `STAGED_INSTALL_ISSUE.md` for full technical details.

## Solution

**Switch from universal binaries to architecture-specific (thin) binaries.**

sherpa-onnx provides architecture-specific builds in their JNI releases:
- `sherpa-onnx-v1.12.17-osx-arm64-jni.tar.bz2` - arm64 only
- `sherpa-onnx-v1.12.17-osx-x86_64-jni.tar.bz2` - x86_64 only

These contain the exact same libraries (`libsherpa-onnx-c-api.dylib`, `libonnxruntime.dylib`, etc.) but as single-architecture binaries.

## Changes Made

### 1. Updated `configure` Script

**Before**:
```bash
Darwin)
  PLATFORM="osx-universal2"
  ARCHIVE="sherpa-onnx-v1.12.17-osx-universal2-shared.tar.bz2"
  LIB_EXT="dylib"
  ;;
```

**After**:
```bash
Darwin)
  # Use architecture-specific (thin) binaries from JNI builds
  # This avoids R's staged install bug with universal binaries
  if [ "$ARCH" = "arm64" ]; then
    PLATFORM="osx-arm64"
    ARCHIVE="sherpa-onnx-v1.12.17-osx-arm64-jni.tar.bz2"
  elif [ "$ARCH" = "x86_64" ]; then
    PLATFORM="osx-x86_64"
    ARCHIVE="sherpa-onnx-v1.12.17-osx-x86_64-jni.tar.bz2"
  else
    echo "ERROR: Unsupported macOS architecture: $ARCH"
    exit 1
  fi
  LIB_EXT="dylib"
  ;;
```

### 2. Updated Documentation

- **CLAUDE.md**: Removed `--no-staged-install` requirement from installation instructions
- Added note about thin binaries resolving staged install issues
- Updated binary size estimate: 31-34 MB (down from ~60 MB for universal)

## Verification

### Before (Universal Binary)
```bash
$ lipo -info inst/libs/libsherpa-onnx-c-api.dylib
Architectures in the fat file: libsherpa-onnx-c-api.dylib are: x86_64 arm64

$ R CMD INSTALL sherpa.onnx_0.1.0.tar.gz
...
ERROR: some hard-coded temporary paths could not be fixed
```

### After (Thin Binary)
```bash
$ lipo -info inst/libs/libsherpa-onnx-c-api.dylib
Non-fat file: inst/libs/libsherpa-onnx-c-api.dylib is architecture: arm64

$ R CMD INSTALL sherpa.onnx_0.1.0.tar.gz
...
** checking absolute paths in shared objects and dynamic libraries
** testing if installed package can be loaded from final location
** testing if installed package keeps a record of temporary installation path
* DONE (sherpa.onnx)
```

### Package Functionality Test
```r
library(sherpa.onnx)
rec <- OfflineRecognizer$new(model = "whisper-tiny")
# ✅ Recognizer created successfully
```

## Benefits

1. ✅ **Staged Install Works** - No need for `--no-staged-install` flag
2. ✅ **Smaller Download** - Architecture-specific binaries are ~50% smaller
3. ✅ **Fully Functional** - All package features work correctly
4. ✅ **Standard Installation** - Works with default `R CMD INSTALL`

## Trade-offs

### Minimal
- Users need to install the correct architecture for their system (automatic via `uname -m`)
- Requires separate builds for Intel and Apple Silicon Macs (already provided by sherpa-onnx)

### Not Applicable
- No need to build universal binaries ourselves
- No cross-compilation required
- sherpa-onnx already provides both architectures

## Testing Performed

1. ✅ Configure script downloads correct architecture
2. ✅ Binaries verified as thin (single architecture)
3. ✅ Package builds successfully
4. ✅ Staged install completes without errors
5. ✅ Package loads in R
6. ✅ Recognizer creation works
7. ✅ Model download and inference functional

## Files Modified

- `configure` - Updated to download architecture-specific binaries
- `CLAUDE.md` - Removed `--no-staged-install` requirement
- `STAGED_INSTALL_ISSUE.md` - Created (technical documentation)
- `THIN_BINARY_FIX.md` - Created (this file)

## For Package Maintainers

If you encounter similar staged install issues with universal binaries:

1. Check if upstream provides architecture-specific builds
2. Update your configure script to detect `uname -m` and download the appropriate binary
3. Verify binaries are thin: `lipo -info library.dylib`
4. Test with standard `R CMD INSTALL` (no flags)

See `STAGED_INSTALL_ISSUE.md` for details on the underlying R bug and potential fixes for R Core.

## References

- sherpa-onnx releases: https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.12.17
- R source code: `src/library/tools/R/install.R` (function `patch_rpaths`)
- Technical details: `STAGED_INSTALL_ISSUE.md`
