# Cider — Third-party notices

Cider itself (the Swift app, build scripts and the `steamwebhelper.exe` wrapper) is released
under the MIT License (see `LICENSE` in the source tree; the wrapper source,
`webhelper_wrapper.c`, is included in this folder).

Cider bundles the following free software in `Cider.app/Contents/Resources/runtime/`.
**Steam is not bundled**: it is downloaded from Valve (`SteamSetup.exe`) on first run.
No Apple D3DMetal / Game Porting Toolkit components are included.

## Wine 11.21 — LGPL-2.1-or-later
- Copyright (c) 1993-2026 the Wine project authors (see `Wine-AUTHORS.txt`).
- License text: `Wine-COPYING.LIB.txt`.
- Binary build: Gcenx "wine-devel 11.21 osx64",
  https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/wine-devel-11.21-osx64.tar.xz
  (SHA-256 9909b486657e10ab66c7279371ae1f990345b596b3b1b3a0cf21f28af24fa0ce).
  Source for that build: https://github.com/Gcenx/macOS_Wine_builds and
  https://dl.winehq.org/wine/source/11.x/wine-11.21.tar.xz
- Modification made by Cider: `lib/wine/x86_64-unix/winemac.so` is rebuilt from the wine-11.21
  source tarball with `CFLAGS=-fvisibility=default` (so DXMT can find the Mac driver's functions)
  and the patches included in this folder: `0001-winemac-resizable-game-windows.patch` (macOS
  minimize/resize/full-screen controls on game windows), `0002-winemac-render-scale.patch`
  (optional lower render resolution, scaled up by macOS) and
  `0003-winemac-metal-view-keeps-contents-scale.patch`. Exact build commands:
  `scripts/build-runtime.sh`.
- Wine Mono and Wine Gecko are **not** included.
- Libraries shipped inside the Gcenx build keep their own licenses: GStreamer (LGPL-2.1),
  GnuTLS / nettle / libtasn1 / p11-kit / libunistring / libidn2 (LGPL), FreeType (FTL/GPL-2),
  SDL2 (zlib), libpng (libpng), zlib (zlib), libxml2 / libxslt (MIT), libffi (MIT),
  ICU (Unicode-3.0), bzip2 (bzip2 license), brotli (MIT), lz4 (BSD-2), xz (0BSD/public domain), zstd (BSD-3),
  libiconv / libintl (LGPL), gmp (LGPL-3), libpcap (BSD-3), libinotify (MIT),
  Vulkan loader (Apache-2.0), MacPorts legacy support (MIT/APSL).
  Their sources are available from the Gcenx build repository above.

## DXMT — MIT
- Copyright (c) 2023 Feifan He. License text: `DXMT-LICENSE.txt`.
- Source: https://github.com/notpop/dxmt at commit 924a607 (fork of https://github.com/3Shain/dxmt),
  plus the patches in this folder:
  `0001-metal-xcode27-threadgroup-atomic.patch` (backport of upstream 3Shain/dxmt commit
  06065754af91352caaf8db87d4566fecc4124552) and `0002-com_guid-include-iomanip.patch`.
- DXMT statically links **LLVM 15.0.7** (Apache-2.0 WITH LLVM-exception, `LLVM-LICENSE.txt`),
  https://github.com/llvm/llvm-project/tree/llvmorg-15.0.7

## MoltenVK — Apache-2.0
Shipped as `libMoltenVK.dylib` inside the Gcenx Wine build. License: `MoltenVK-LICENSE.txt`.
https://github.com/KhronosGroup/MoltenVK

## Trademarks
Steam and the Steam logo are trademarks of Valve Corporation. Windows and DirectX are
trademarks of Microsoft. Cider is not affiliated with Valve, Microsoft or Apple.
