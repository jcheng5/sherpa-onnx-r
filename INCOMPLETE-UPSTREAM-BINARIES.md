# Incomplete Upstream Binaries

## Summary

During investigation of adding Linux aarch64 support to the sherpa.onnx R package, we discovered inconsistencies in the sherpa-onnx prebuilt binary releases. The R package requires both:
1. C API headers (`include/sherpa-onnx/c-api/c-api.h`)
2. C API library (`libsherpa-onnx-c-api.so` or `.dylib`)

However, not all upstream builds include both components.

## Build Comparison

| Platform | Build Type | Headers | C API Lib | Works for R? | Archive Name |
|----------|-----------|---------|-----------|--------------|--------------|
| **macOS x64** | JNI | ✅ Yes | ✅ Yes | ✅ **Yes** | `sherpa-onnx-v1.12.17-osx-x86_64-jni.tar.bz2` |
| **macOS arm64** | JNI | ✅ Yes | ✅ Yes | ✅ **Yes** | `sherpa-onnx-v1.12.17-osx-arm64-jni.tar.bz2` |
| **Linux x64** | shared | ✅ Yes | ✅ Yes | ✅ **Yes** | `sherpa-onnx-v1.12.17-linux-x64-shared.tar.bz2` |
| **Linux x64** | JNI | ✅ Yes | ❌ Removed | ❌ No | `sherpa-onnx-v1.12.17-linux-x64-jni.tar.bz2` |
| **Linux aarch64** | shared-cpu | ❌ Missing | ✅ Yes | ❌ No | `sherpa-onnx-v1.12.17-linux-aarch64-shared-cpu.tar.bz2` |
| **Linux aarch64** | JNI | ✅ Yes | ❌ Removed | ❌ No | `sherpa-onnx-v1.12.17-linux-aarch64-jni.tar.bz2` |

## Current R Package Status

- ✅ **macOS (x64 & arm64)**: Using JNI builds, fully functional
- ✅ **Linux x64**: Using shared build, fully functional
- ❌ **Linux aarch64**: No single build has both components

## Detailed Findings

### macOS JNI Builds (Working)

The macOS JNI builds are complete and work perfectly:

```bash
sherpa-onnx-v1.12.17-osx-arm64-jni/
├── include/
│   └── sherpa-onnx/c-api/
│       ├── c-api.h          ✅
│       └── cxx-api.h
└── lib/
    ├── libsherpa-onnx-c-api.dylib       ✅
    ├── libsherpa-onnx-jni.dylib
    ├── libsherpa-onnx-cxx-api.dylib
    └── libonnxruntime.dylib
```

**GitHub Actions workflow**: `.github/workflows/macos-jni.yaml`
- Does NOT remove `libsherpa-onnx-c-api.dylib`
- Copies headers: `cp -a build/install/include $dst/`

### Linux x64 Shared Build (Working)

The Linux x64 shared build is complete:

```bash
sherpa-onnx-v1.12.17-linux-x64-shared/
├── include/
│   └── sherpa-onnx/c-api/
│       ├── c-api.h          ✅
│       └── cxx-api.h
└── lib/
    ├── libsherpa-onnx-c-api.so          ✅
    ├── libsherpa-onnx-cxx-api.so
    └── libonnxruntime.so
```

**GitHub Actions workflow**: `.github/workflows/linux.yaml:190-195`
```bash
cp -a build/install/bin $dst/
if [[ ${{ matrix.shared_lib }} == ON ]]; then
  mkdir $dst/lib
  cp -av build/install/lib/*.so* $dst/lib/
fi
cp -a build/install/include $dst/    # ✅ Includes headers
```

### Linux x64 JNI Build (Incomplete)

The Linux x64 JNI build has headers but **explicitly removes** the C API library:

```bash
sherpa-onnx-v1.12.17-linux-x64-jni/
├── include/
│   └── sherpa-onnx/c-api/
│       ├── c-api.h          ✅
│       └── cxx-api.h
└── lib/
    ├── libsherpa-onnx-jni.so
    ├── libsherpa-onnx-cxx-api.so
    └── libonnxruntime.so
    # ❌ Missing: libsherpa-onnx-c-api.so
```

**GitHub Actions workflow**: `.github/workflows/linux-jni.yaml:144-145`
```bash
rm -rf ./install/lib/libsherpa-onnx-c-api.so    # ❌ Explicitly removed!
rm -rf ./install/lib/libsherpa-onnx-cxx-api.so
```

### Linux aarch64 Shared Build (Incomplete)

The Linux aarch64 shared build has the C API library but **is missing headers entirely**:

```bash
sherpa-onnx-v1.12.17-linux-aarch64-shared-cpu/
├── bin/
│   └── [various binaries]
└── lib/
    ├── libsherpa-onnx-c-api.so          ✅
    ├── libsherpa-onnx-cxx-api.so
    └── libonnxruntime.so
# ❌ Missing: include/ directory entirely
```

**GitHub Actions workflow**: `.github/workflows/aarch64-linux-gnu-shared.yaml:185-186`
```bash
cp -a build/install/bin $dst/
cp -a build/install/lib $dst/
# ❌ Missing: cp -a build/install/include $dst/
```

**This is a bug** - compare with the x64 shared build which correctly includes headers.

### Linux aarch64 JNI Build (Incomplete)

The Linux aarch64 JNI build has headers but **explicitly removes** the C API library:

```bash
sherpa-onnx-v1.12.17-linux-aarch64-jni/
├── include/
│   └── sherpa-onnx/c-api/
│       ├── c-api.h          ✅
│       └── cxx-api.h
└── lib/
    ├── libsherpa-onnx-jni.so
    ├── libsherpa-onnx-cxx-api.so
    └── libonnxruntime.so
    # ❌ Missing: libsherpa-onnx-c-api.so
```

**GitHub Actions workflow**: `.github/workflows/linux-jni-aarch64.yaml:110`
```bash
rm -rf ./install/lib/libsherpa-onnx-c-api.so    # ❌ Explicitly removed!
```

## Root Causes

### Issue 1: Linux JNI Builds Remove C API Library

The Linux JNI builds (both x64 and aarch64) explicitly remove `libsherpa-onnx-c-api.so`, while the macOS JNI builds do not. This inconsistency makes Linux JNI builds unsuitable for C API usage.

**Why?** The JNI builds are intended for Java usage only, and the maintainers likely want to keep the package size smaller. However, this creates an inconsistency with macOS JNI builds.

### Issue 2: Linux aarch64 Shared Build Missing Headers

The Linux aarch64 shared build workflow is missing a single line that copies headers. This is clearly a bug, as the x64 shared build includes this line.

**Fix needed in** `.github/workflows/aarch64-linux-gnu-shared.yaml` at line ~187:
```bash
cp -a build/install/bin $dst/
cp -a build/install/lib $dst/
cp -a build/install/include $dst/    # ← ADD THIS LINE
```

## Workarounds for Linux aarch64

Until upstream fixes are available, these workarounds exist:

### Option 1: Download Both Archives (Hacky)

Download both the shared-cpu (for libs) and JNI (for headers) builds and merge them:

```bash
# Download shared-cpu for libraries
curl -L -O https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.17/sherpa-onnx-v1.12.17-linux-aarch64-shared-cpu.tar.bz2

# Download JNI for headers
curl -L -O https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.17/sherpa-onnx-v1.12.17-linux-aarch64-jni.tar.bz2

# Extract and merge
tar xjf sherpa-onnx-v1.12.17-linux-aarch64-shared-cpu.tar.bz2
tar xjf sherpa-onnx-v1.12.17-linux-aarch64-jni.tar.bz2
cp -r sherpa-onnx-v1.12.17-linux-aarch64-jni/include/ \
      sherpa-onnx-v1.12.17-linux-aarch64-shared-cpu/
```

**Total download size**: ~60MB (both archives combined)

### Option 2: Use System Installation

Set `SHERPA_ONNX_USE_SYSTEM=1` and build/install sherpa-onnx from source:

```bash
export SHERPA_ONNX_USE_SYSTEM=1
R CMD INSTALL sherpa.onnx_*.tar.gz
```

### Option 3: Wait for Upstream Fix

Report the issue to k2-fsa/sherpa-onnx and wait for:
1. Linux aarch64 shared build to include headers
2. Or Linux aarch64 JNI build to keep C API library (like macOS)

## Recommendations

1. **Report upstream** to k2-fsa/sherpa-onnx:
   - Linux aarch64 shared build missing headers (clear bug)
   - Inconsistency: Linux JNI removes C API lib, macOS JNI keeps it

2. **For now**: Document in R package that Linux aarch64 requires system installation

3. **Long term**: Once upstream is fixed, update configure script to use the appropriate build

## Upstream Repository

- **GitHub**: https://github.com/k2-fsa/sherpa-onnx
- **Workflows**: `.github/workflows/`
- **Issue tracker**: https://github.com/k2-fsa/sherpa-onnx/issues

## Date

This investigation was conducted on 2024-11-30 with sherpa-onnx version 1.12.17.
