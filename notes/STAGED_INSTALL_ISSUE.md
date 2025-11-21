# R Staged Install Failure with Universal Binary Libraries

## Overview

R's staged install mechanism fails when R packages contain **universal (fat) binary** dynamic libraries on macOS. This document explains the technical cause, provides evidence, and suggests workarounds and fixes.

**TL;DR**: R's `patch_rpaths()` function in `tools:::install.R` only removes the first line of `otool -l` output, but universal binaries produce two architecture headers. The second header contains the temporary installation path, causing a false positive in the hardcoded path check.

**Workaround**: Use `R CMD INSTALL --no-staged-install` for packages with universal binary dependencies.

---

## Background

### What is Staged Install?

Starting with R 3.6.0, `R CMD INSTALL` uses "staged installation" by default:

1. The package is first installed to a temporary directory (e.g., `/Library/.../00LOCK-pkg/00new/pkg/`)
2. R checks and patches any hardcoded paths in shared libraries
3. The package is moved to the final installation location

This ensures shared libraries use relative paths (like `@loader_path` or `$ORIGIN`) rather than absolute paths that would break if the package is moved.

### What are Universal Binaries?

Universal binaries (also called "fat binaries") contain code for multiple CPU architectures in a single file. On macOS, this typically means x86_64 (Intel) and arm64 (Apple Silicon) combined:

```bash
$ lipo -info libsherpa-onnx-c-api.dylib
Architectures in the fat file: libsherpa-onnx-c-api.dylib are: x86_64 arm64
```

This allows a single binary to run natively on both Intel and Apple Silicon Macs.

---

## The Problem

### Symptom

During `R CMD INSTALL`, the package builds successfully but fails during the staged install check:

```
** testing if installed package can be loaded from temporary location
** checking absolute paths in shared objects and dynamic libraries
ERROR: some hard-coded temporary paths could not be fixed
```

### Root Cause

The bug is in R's `patch_rpaths()` function in `src/library/tools/R/install.R` (lines 810-814):

```r
## check no hard-coded paths are left
out <- suppressWarnings(
    system(paste("otool -l", shQuote(l)), intern = TRUE))
out <- out[-1L] # first line is l (includes instdir)
if (any(grepl(instdir, out, fixed = TRUE)))
    failed_fix <- TRUE
```

The comment states "first line is l (includes instdir)", and the code removes exactly one line with `out[-1L]`.

### The Issue with Universal Binaries

For **single-architecture** binaries, `otool -l` produces:

```
/path/to/lib.dylib:
Load command 0
  cmd LC_SEGMENT_64
  ...
```

After removing the first line (`out[-1L]`), the path is gone.

For **universal binaries**, `otool -l` produces:

```
/path/to/lib.dylib (architecture x86_64):
Load command 0
  cmd LC_SEGMENT_64
  ...
/path/to/lib.dylib (architecture arm64):
Load command 0
  cmd LC_SEGMENT_64
  ...
```

After removing only the first line, the second architecture header still contains the path. If this path includes `instdir` (the temporary installation directory like `00LOCK-pkg/00new/pkg`), the grep finds it and sets `failed_fix <- TRUE`.

---

## Evidence

### Test Case: sherpa-onnx R Package

The sherpa-onnx R package bundles pre-built universal binaries:

```bash
$ file inst/libs/libsherpa-onnx-c-api.dylib
inst/libs/libsherpa-onnx-c-api.dylib: Mach-O universal binary with 2 architectures:
[x86_64:Mach-O 64-bit dynamically linked shared library x86_64] [arm64]

$ lipo -info inst/libs/libsherpa-onnx-c-api.dylib
Architectures in the fat file: inst/libs/libsherpa-onnx-c-api.dylib are: x86_64 arm64
```

These libraries are correctly built with **relative paths**:

```bash
$ otool -D inst/libs/libsherpa-onnx-c-api.dylib
inst/libs/libsherpa-onnx-c-api.dylib (architecture x86_64):
@rpath/libsherpa-onnx-c-api.dylib
inst/libs/libsherpa-onnx-c-api.dylib (architecture arm64):
@rpath/libsherpa-onnx-c-api.dylib

$ otool -L inst/libs/libsherpa-onnx-c-api.dylib
inst/libs/libsherpa-onnx-c-api.dylib (architecture x86_64):
	@rpath/libsherpa-onnx-c-api.dylib (compatibility version 0.0.0, current version 0.0.0)
	@rpath/libonnxruntime.1.17.1.dylib (compatibility version 0.0.0, current version 1.17.1)
	/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1351.0.0)
	/usr/lib/libc++.1.dylib (compatibility version 1.0.0, current version 1900.180.0)
```

The rpath is set correctly to `@loader_path`:

```bash
$ otool -l inst/libs/libsherpa-onnx-c-api.dylib | grep -A3 "LC_RPATH"
          cmd LC_RPATH
      cmdsize 32
         path @loader_path (offset 12)
```

### Demonstrating the Bug

When these libraries are installed to a temporary location during staged install:

```bash
$ mkdir -p /tmp/test_install/libs
$ cp inst/libs/libsherpa-onnx-c-api.dylib /tmp/test_install/libs/

$ otool -l /tmp/test_install/libs/libsherpa-onnx-c-api.dylib | head -5
/tmp/test_install/libs/libsherpa-onnx-c-api.dylib (architecture x86_64):
Load command 0
      cmd LC_SEGMENT_64
  cmdsize 632
  segname __TEXT
```

After R removes the first line with `out[-1L]`, the output continues with more load commands, followed by:

```
/tmp/test_install/libs/libsherpa-onnx-c-api.dylib (architecture arm64):
Load command 0
  ...
```

The second architecture header still contains `/tmp/test_install`, which matches `instdir` during staged install, causing the false positive.

### Confirming Libraries Are Correctly Built

Despite the false positive, the libraries work perfectly:

1. **No absolute paths in dependencies**: All dependencies use `@rpath`
2. **Proper rpath configuration**: Uses `@loader_path` for relative paths
3. **Successfully loads with `--no-staged-install`**: The package works correctly when staged install is bypassed

---

## Impact

### Affected Packages

Any R package that bundles universal binary dynamic libraries on macOS will fail staged install, including:

- Packages with pre-built binaries from upstream projects
- Packages using system libraries compiled as universal binaries
- Packages that download and bundle macOS .dylib files

### Current Workaround

The only workaround is to disable staged install:

```bash
R CMD INSTALL --no-staged-install package.tar.gz
```

This is documented in the sherpa-onnx package's `CLAUDE.md`:

```bash
cd ..
R CMD build sherpa-onnx-r
R CMD INSTALL --no-staged-install sherpa.onnx_0.1.0.tar.gz
```

---

## Proposed Solutions

### For R Core Maintainers

**Fix in `src/library/tools/R/install.R`** (around line 810):

Instead of removing only the first line:

```r
out <- out[-1L] # first line is l (includes instdir)
```

Remove **all** architecture header lines. The fix should handle both single-arch and multi-arch binaries:

```r
# Remove all lines that are architecture headers (contain the library path)
# Single-arch: "path/to/lib.dylib:"
# Multi-arch:  "path/to/lib.dylib (architecture x86_64):"
#              "path/to/lib.dylib (architecture arm64):"
out <- out[!grepl(paste0("^", basename(l)), out)]
```

Or more precisely:

```r
# Remove the first line and any additional architecture headers
# Architecture headers match the pattern: "filepath (architecture <arch>):"
out <- suppressWarnings(
    system(paste("otool -l", shQuote(l)), intern = TRUE))

# Remove first line (always contains path)
if (length(out) > 0) out <- out[-1L]

# Remove any additional architecture headers (for universal binaries)
# These have the format: "path/to/lib.dylib (architecture arm64):"
out <- out[!grepl("^[^:]+\\(architecture [^)]+\\):", out)]

if (any(grepl(instdir, out, fixed = TRUE)))
    failed_fix <- TRUE
```

### For R Package Authors

**When bundling pre-built libraries**:

1. **Document the `--no-staged-install` requirement** in `DESCRIPTION`, `README.md`, and installation instructions
2. **Add to package metadata** (if possible in future R versions):
   ```
   StagedInstall: no
   ```
3. **Ensure libraries use relative paths**: Verify with `otool -L` that all dependencies use `@rpath` or `@loader_path`
4. **Test on both architectures**: If shipping universal binaries, test on both Intel and Apple Silicon Macs

**Example package documentation** (from sherpa-onnx):

```md
## Building and Installing

**Important**: Must use `--no-staged-install` flag due to universal binary libraries:

\`\`\`bash
R CMD build sherpa-onnx-r
R CMD INSTALL --no-staged-install sherpa.onnx_0.1.0.tar.gz
\`\`\`
```

### For Upstream Library Maintainers

**When building libraries for R packages**:

1. **Use relative paths**: Set library ID and rpaths to use `@loader_path`:
   ```bash
   install_name_tool -id "@rpath/libname.dylib" libname.dylib
   install_name_tool -add_rpath "@loader_path" libname.dylib
   ```

2. **Ensure dependencies use `@rpath`**: All library dependencies should reference `@rpath/`:
   ```bash
   install_name_tool -change /absolute/path/libdep.dylib @rpath/libdep.dylib libname.dylib
   ```

3. **Test relocation**: Verify libraries work from different locations:
   ```bash
   # Copy library to different directory
   cp libname.dylib /tmp/test/
   # Verify it still resolves dependencies
   otool -L /tmp/test/libname.dylib
   ```

4. **Document universal binary implications**: Note that universal binaries may require `--no-staged-install` in R packages until R fixes this bug

---

## Testing

### Minimal Reproducible Example

Create a test R package with a universal binary:

```bash
# 1. Create minimal package structure
mkdir -p testpkg/src testpkg/inst/libs testpkg/R

# 2. Copy any universal binary to inst/libs/
cp /path/to/universal.dylib testpkg/inst/libs/

# 3. Create minimal DESCRIPTION
cat > testpkg/DESCRIPTION <<EOF
Package: testpkg
Version: 0.1.0
Title: Test Package
Description: Test universal binary staged install
Author: Test
Maintainer: Test <test@example.com>
License: GPL-3
EOF

# 4. Try to install
R CMD build testpkg
R CMD INSTALL testpkg_0.1.0.tar.gz  # Will fail

R CMD INSTALL --no-staged-install testpkg_0.1.0.tar.gz  # Will succeed
```

### Verification

Confirm the libraries are correctly built:

```bash
# Check for relative paths
otool -D inst/libs/*.dylib | grep @rpath

# Check dependencies use @rpath
otool -L inst/libs/*.dylib | grep @rpath

# Check rpath entries
otool -l inst/libs/*.dylib | grep -A2 LC_RPATH

# Verify it's a universal binary
lipo -info inst/libs/*.dylib
```

---

## References

- R Staged Install Documentation: https://cran.r-project.org/doc/manuals/r-devel/R-exts.html#Package-subdirectories
- R Source Code: `src/library/tools/R/install.R` (function `patch_rpaths`, line ~638-930)
- Apple Documentation on `@rpath`: https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/DynamicLibraries/
- sherpa-onnx R Package: https://github.com/k2-fsa/sherpa-onnx

---

## Conclusion

This is a fixable bug in R's staged install process that affects packages with universal binary libraries. The fix is straightforward: properly handle multiple architecture headers in `otool -l` output by removing all path-containing header lines, not just the first one.

Until R Core implements this fix, package authors should:
1. Document the `--no-staged-install` requirement
2. Ensure bundled libraries use relative paths
3. Test on multiple architectures

**Version Information** (when this document was created):
- R version: 4.5.1
- macOS: Darwin 25.1.0
- Platform: Apple Silicon (arm64)
- Date: 2025-11-21
