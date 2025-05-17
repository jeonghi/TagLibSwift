#!/bin/bash
set -e

# 설정
TAGLIB_DIR=taglib
INSTALL_DIR=install
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_FILE="$SCRIPT_DIR/ios-cmake/ios.toolchain.cmake"

# 초기화
rm -rf build-ios build-macos "$INSTALL_DIR" TagLib.xcframework
mkdir -p "$INSTALL_DIR"

echo "📦 TagLib iOS 빌드 시작..."

# ----------------------
# iOS 빌드 (device + simulator 통합)
# PostBuild install 단계는 생략 (ALL_BUILD만 사용)
# ----------------------
cmake -S "$TAGLIB_DIR" -B build-ios \
  -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE" \
  -DPLATFORM=OS64COMBINED \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR/ios" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_BINDINGS=OFF

cmake --build build-ios --config Release --target ALL_BUILD

# 수동 복사 (lib + headers)
mkdir -p "$INSTALL_DIR/ios/lib"
mkdir -p "$INSTALL_DIR/ios/include"
cp -a build-ios/taglib/Release-iphoneos/libtag.a "$INSTALL_DIR/ios/lib/libtag.a"
cp -a "$TAGLIB_DIR/taglib" "$INSTALL_DIR/ios/include"

echo "📦 TagLib macOS 빌드 시작..."

# ----------------------
# macOS 빌드 (install 사용 가능)
# ----------------------
cmake -S "$TAGLIB_DIR" -B build-macos \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR/macos" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_BINDINGS=OFF

cmake --build build-macos --target install

# ----------------------
# XCFramework 생성
# ----------------------
xcodebuild -create-xcframework \
  -library "$INSTALL_DIR/ios/lib/libtag.a" -headers "$INSTALL_DIR/ios/include" \
  -library "$INSTALL_DIR/macos/lib/libtag.a" -headers "$INSTALL_DIR/macos/include" \
  -output TagLib.xcframework

echo -e "\n✅ TagLib.xcframework 생성 완료!"