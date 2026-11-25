#!/bin/bash
# Builds Cider's Windows runtime into build/runtime/:
#   wine/                Wine 11.21 (Gcenx build) + winemac.so rebuilt with visible symbols + DXMT
#   steamwebhelper.exe   our wrapper around Steam's CEF browser
#   licenses/            notices for everything we redistribute
#
# Everything downloaded or compiled is cached under third_party/ so re-runs are fast.
#
# Optional environment:
#   CIDER_SEED_DIRS   colon-separated dirs searched for already-downloaded archives (matched by SHA-256)
#   CIDER_LLVM_PREFIX an existing LLVM 15.0.7 x86_64 install (static libs) to clone instead of
#                     compiling it (~30 min). It is cloned with `cp -c` (APFS copy-on-write), never modified.
#   CIDER_WINE_TC     an existing 3Shain wine toolchain (v8.16-3shain) to clone instead of downloading.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Optional machine-specific settings (not committed), see scripts/local.env.example.
[ -f "$ROOT/scripts/local.env" ] && . "$ROOT/scripts/local.env"
TP="$ROOT/third_party"
DL="$TP/downloads"
SRC="$TP/src"
TC="$TP/toolchains"
OUT="$ROOT/build/runtime"
JOBS="$(sysctl -n hw.logicalcpu)"
mkdir -p "$DL" "$SRC" "$TC"

log() { printf '\033[1;35m==>\033[0m %s\n' "$*"; }

WINE_VER=11.21
GCENX_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/$WINE_VER/wine-devel-$WINE_VER-osx64.tar.xz"
GCENX_SHA=9909b486657e10ab66c7279371ae1f990345b596b3b1b3a0cf21f28af24fa0ce
WINE_SRC_URL="https://dl.winehq.org/wine/source/11.x/wine-$WINE_VER.tar.xz"
DXMT_REPO=https://github.com/notpop/dxmt.git
DXMT_COMMIT=924a607
WINE_TC_URL=https://github.com/3Shain/wine/releases/download/v8.16-3shain/wine.tar.gz
LLVM_TAG=llvmorg-15.0.7

SEED_DIRS="${CIDER_SEED_DIRS:-}"

# fetch <url> <dest> [sha256]
fetch() {
  local url="$1" dest="$2" sha="${3:-}"
  if [ -f "$dest" ] && { [ -z "$sha" ] || [ "$(shasum -a 256 "$dest" | cut -d' ' -f1)" = "$sha" ]; }; then return 0; fi
  if [ -n "$sha" ]; then
    local IFS=:
    for d in $SEED_DIRS; do
      for f in "$d"/*; do
        [ -f "$f" ] || continue
        if [ "$(stat -f %z "$f")" -gt 1000000 ] && [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" = "$sha" ]; then
          log "Using cached copy of $(basename "$dest") from $f"
          cp -c "$f" "$dest"; return 0
        fi
      done
    done
    unset IFS
  fi
  log "Downloading $url"
  curl -fL --retry 3 -o "$dest.part" "$url"
  if [ -n "$sha" ] && [ "$(shasum -a 256 "$dest.part" | cut -d' ' -f1)" != "$sha" ]; then
    echo "Checksum mismatch for $url" >&2; exit 1
  fi
  mv "$dest.part" "$dest"
}

# ---------------------------------------------------------------- 1. Wine (Gcenx)
fetch "$GCENX_URL" "$DL/wine-devel-$WINE_VER-osx64.tar.xz" "$GCENX_SHA"
if [ ! -x "$SRC/gcenx/Wine Devel.app/Contents/Resources/wine/bin/wine" ]; then
  log "Extracting Gcenx Wine $WINE_VER"
  rm -rf "$SRC/gcenx"; mkdir -p "$SRC/gcenx"
  tar -xJf "$DL/wine-devel-$WINE_VER-osx64.tar.xz" -C "$SRC/gcenx"
fi
GCENX_WINE="$SRC/gcenx/Wine Devel.app/Contents/Resources/wine"

# ---------------------------------------------------------------- 2. winemac.so with visible symbols
# Cache key: our winemac patches.
WINE_PATCH_ID=$(cat "$ROOT"/patches/wine/*.patch 2>/dev/null | shasum | cut -c1-10)
WINEMAC="$TP/cache/winemac-$WINE_PATCH_ID.so"
if [ ! -f "$WINEMAC" ]; then
  fetch "$WINE_SRC_URL" "$DL/wine-$WINE_VER.tar.xz"
  if [ ! -f "$SRC/wine-$WINE_VER/configure" ]; then
    log "Extracting Wine $WINE_VER sources"
    tar -xJf "$DL/wine-$WINE_VER.tar.xz" -C "$SRC"
  fi
  for p in "$ROOT"/patches/wine/*.patch; do
    # Skip patches that are already applied (reverse dry-run succeeds).
    if ! patch -d "$SRC/wine-$WINE_VER" -p1 -R -s -f --dry-run < "$p" >/dev/null 2>&1; then
      log "Applying $(basename "$p")"
      patch -d "$SRC/wine-$WINE_VER" -p1 -s < "$p"
    fi
  done
  export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"
  mkdir -p "$SRC/wine-$WINE_VER/build"
  pushd "$SRC/wine-$WINE_VER/build" >/dev/null
  if [ ! -f Makefile ]; then
    log "Configuring Wine (x86_64, only to build winemac.so)"
    # CC must carry -arch x86_64 explicitly, otherwise configure mixes arm64/i386 headers.
    arch -x86_64 ../configure \
      --enable-win64 --disable-tests \
      --without-x --without-freetype --without-gnutls --without-gstreamer \
      --without-sdl --without-cups --without-sane --without-usb --without-v4l2 \
      --without-pcap --without-krb5 --without-netapi --without-gphoto \
      CC='clang -arch x86_64' CXX='clang++ -arch x86_64' \
      CFLAGS='-fvisibility=default -O2 -Wno-error' \
      CXXFLAGS='-fvisibility=default -O2 -Wno-error' >"$TP/wine-configure.log" 2>&1
  fi
  log "Building winemac.so"
  arch -x86_64 make -j"$JOBS" dlls/winemac.drv/winemac.so >"$TP/wine-make.log" 2>&1
  n=$(nm -g dlls/winemac.drv/winemac.so | awk '$2=="T"' | wc -l | tr -d ' ')
  log "winemac.so exports $n symbols"
  [ "$n" -ge 100 ] || { echo "winemac.so still hides its symbols" >&2; exit 1; }
  mkdir -p "$TP/cache"; cp dlls/winemac.drv/winemac.so "$WINEMAC"
  popd >/dev/null
fi

# ---------------------------------------------------------------- 3. DXMT
DXMT_PATCH_ID=$(cat "$ROOT"/patches/dxmt/*.patch | shasum | cut -c1-10)
DXMT_OUT="$TP/cache/dxmt-$DXMT_PATCH_ID"
if [ ! -f "$DXMT_OUT/x86_64-unix/winemetal.so" ]; then
  D="$SRC/dxmt"
  if [ ! -d "$D/.git" ]; then
    log "Cloning DXMT ($DXMT_REPO @ $DXMT_COMMIT)"
    git clone --quiet "$DXMT_REPO" "$D"
    git -C "$D" checkout --quiet "$DXMT_COMMIT"
    git -C "$D" submodule update --init --recursive --quiet
  fi
  # Apply any of our patches not applied yet (they are idempotent-checked with --check).
  for p in "$ROOT"/patches/dxmt/*.patch; do
    if git -C "$D" apply --check "$p" 2>/dev/null; then
      log "Applying $(basename "$p")"
      git -C "$D" apply "$p"
    fi
  done

  # meson 1.10+ breaks this cross build: pin it.
  if [ ! -x "$TC/meson-venv/bin/meson" ]; then
    python3 -m venv --clear "$TC/meson-venv"
    "$TC/meson-venv/bin/pip" install --quiet --disable-pip-version-check "meson==1.7.2" ninja
  fi
  export PATH="$TC/meson-venv/bin:$PATH"

  # LLVM 15 x86_64 (static). Clone an existing build when available.
  LLVM_SEED="${CIDER_LLVM_PREFIX:-}"
  if [ ! -f "$TC/llvm/lib/libLLVMCore.a" ]; then
    if [ -f "$LLVM_SEED/lib/libLLVMCore.a" ]; then
      log "Cloning existing LLVM 15 build from $LLVM_SEED"
      rm -rf "$TC/llvm"; cp -cR "$LLVM_SEED" "$TC/llvm"
    else
      log "Building LLVM 15.0.7 for x86_64 (this takes ~30 min, only once)"
      [ -d "$TC/llvm-src" ] || git clone --branch "$LLVM_TAG" --depth 1 https://github.com/llvm/llvm-project.git "$TC/llvm-src"
      cmake -S "$TC/llvm-src/llvm" -B "$TC/llvm-src/build" -G Ninja \
        -DLLVM_ENABLE_PROJECTS="" -DLLVM_TARGETS_TO_BUILD="X86;AArch64" \
        -DLLVM_BUILD_TOOLS=OFF -DLLVM_BUILD_EXAMPLES=OFF -DLLVM_INCLUDE_TESTS=OFF \
        -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_ENABLE_RTTI=ON \
        -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_LIBXML2=OFF \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 \
        -DCMAKE_INSTALL_PREFIX="$TC/llvm"
      cmake --build "$TC/llvm-src/build"
      cmake --install "$TC/llvm-src/build"
    fi
  fi

  # 3Shain's Wine toolchain (headers + winebuild for the unix side of winemetal).
  WINE_TC_SEED="${CIDER_WINE_TC:-}"
  if [ ! -x "$TC/wine/bin/winebuild" ]; then
    if [ -x "$WINE_TC_SEED/bin/winebuild" ]; then
      log "Cloning existing 3Shain Wine toolchain from $WINE_TC_SEED"
      rm -rf "$TC/wine"; cp -cR "$WINE_TC_SEED" "$TC/wine"
    else
      fetch "$WINE_TC_URL" "$DL/wine-3shain-8.16.tar.gz"
      rm -rf "$TC/wine"; mkdir -p "$TC/wine"; tar -xzf "$DL/wine-3shain-8.16.tar.gz" -C "$TC/wine"
      if [ ! -x "$TC/wine/bin/winebuild" ]; then
        n=$(find "$TC/wine" -mindepth 2 -maxdepth 3 -type f -path '*/bin/winebuild' | head -n1)
        r=$(dirname "$(dirname "$n")"); shopt -s dotglob; mv "$r"/* "$TC/wine"/; shopt -u dotglob
      fi
    fi
  fi

  xcrun -f metal >/dev/null 2>&1 || {
    log "Downloading Apple's Metal Toolchain"; xcodebuild -downloadComponent MetalToolchain; }

  pushd "$D" >/dev/null
  [ -d build ] || arch -arm64 meson setup --cross-file build-win64.txt \
    -Dnative_llvm_path="$TC/llvm" -Dwine_install_path="$TC/wine" build --buildtype release \
    >"$TP/dxmt-setup.log" 2>&1
  log "Building DXMT (64-bit)"
  arch -arm64 meson compile -C build >"$TP/dxmt-build.log" 2>&1
  rm -rf "$DXMT_OUT"; mkdir -p "$DXMT_OUT/x86_64-unix" "$DXMT_OUT/x86_64-windows"
  cp build/src/winemetal/unix/winemetal.so "$DXMT_OUT/x86_64-unix/"
  find build -name '*.dll' | while read -r f; do
    case "$(basename "$f")" in d3d11.dll|d3d10core.dll|dxgi.dll|winemetal.dll) cp "$f" "$DXMT_OUT/x86_64-windows/";; esac
  done
  x86_64-w64-mingw32-strip --strip-debug "$DXMT_OUT"/x86_64-windows/*.dll
  strip -x "$DXMT_OUT/x86_64-unix/winemetal.so"
  popd >/dev/null
fi

# ---------------------------------------------------------------- 4. steamwebhelper wrapper
WRAPPER="$TP/cache/steamwebhelper.exe"
if [ ! -f "$WRAPPER" ] || [ "$ROOT/runtime-src/steamwebhelper/webhelper_wrapper.c" -nt "$WRAPPER" ]; then
  log "Compiling steamwebhelper wrapper"
  mkdir -p "$TP/cache"
  x86_64-w64-mingw32-gcc -O2 -municode -mwindows -s -Wl,--no-insert-timestamp -o "$WRAPPER" "$ROOT/runtime-src/steamwebhelper/webhelper_wrapper.c"
fi

# ---------------------------------------------------------------- 5. Assemble
log "Assembling runtime in build/runtime"
rm -rf "$OUT"; mkdir -p "$OUT"
cp -cR "$GCENX_WINE" "$OUT/wine"
# Wine Mono / Gecko are not needed by Steam or DirectX games; leaving them out saves ~300 MB.
rm -rf "$OUT/wine/share/wine/mono" "$OUT/wine/share/wine/gecko"
# winemac.so with exported symbols (needed by DXMT)
cp "$WINEMAC" "$OUT/wine/lib/wine/x86_64-unix/winemac.so"
# DXMT as builtin 64-bit Direct3D 10/11 + DXGI. 32-bit keeps Wine's wined3d.
cp "$DXMT_OUT/x86_64-unix/winemetal.so" "$OUT/wine/lib/wine/x86_64-unix/"
cp "$DXMT_OUT"/x86_64-windows/*.dll "$OUT/wine/lib/wine/x86_64-windows/"
cp "$WRAPPER" "$OUT/steamwebhelper.exe"

# Licenses
L="$OUT/licenses"; mkdir -p "$L"
cp "$ROOT"/licenses/*.md "$L/" 2>/dev/null || true
if [ -f "$SRC/wine-$WINE_VER/COPYING.LIB" ]; then
  cp "$SRC/wine-$WINE_VER/COPYING.LIB" "$L/Wine-COPYING.LIB.txt"
  cp "$SRC/wine-$WINE_VER/AUTHORS" "$L/Wine-AUTHORS.txt"
fi
cp "$SRC/dxmt/LICENSE" "$L/DXMT-LICENSE.txt" 2>/dev/null || true
[ -f "$TC/llvm-src/llvm/LICENSE.TXT" ] && cp "$TC/llvm-src/llvm/LICENSE.TXT" "$L/LLVM-LICENSE.txt"
[ -f "$L/LLVM-LICENSE.txt" ] || fetch "https://raw.githubusercontent.com/llvm/llvm-project/$LLVM_TAG/llvm/LICENSE.TXT" "$L/LLVM-LICENSE.txt"
fetch "https://raw.githubusercontent.com/KhronosGroup/MoltenVK/main/LICENSE" "$TP/cache/MoltenVK-LICENSE.txt"
cp "$TP/cache/MoltenVK-LICENSE.txt" "$L/MoltenVK-LICENSE.txt"
cp "$ROOT"/patches/dxmt/*.patch "$ROOT"/patches/wine/*.patch "$L/" 2>/dev/null || true

du -sh "$OUT"
log "Runtime ready: $OUT"
