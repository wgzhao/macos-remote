#!/usr/bin/env bash
set -euo pipefail

# scripts/build-universal.sh
# Generates an Xcode project from this Swift Package (using `swift package generate-xcodeproj`)
# Builds Release binaries for arm64 and x86_64 and merges them into universal binaries using lipo.
# Usage: ./scripts/build-universal.sh [controlled|controller|both]
# Example: ./scripts/build-universal.sh both

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARM_DERIVED="$BUILD_DIR/derived_arm"
X86_DERIVED="$BUILD_DIR/derived_x86"
UNIVERSAL_DIR="$BUILD_DIR/universal"

SCHEMES=("Controlled" "Controller")

if [[ ${#@} -ge 1 ]]; then
  case "$1" in
    controlled)
      TARGET_SCHEMES=("Controlled")
      ;;
    controller)
      TARGET_SCHEMES=("Controller")
      ;;
    both)
      TARGET_SCHEMES=("Controlled" "Controller")
      ;;
    *)
      echo "Usage: $0 [controlled|controller|both]" >&2
      exit 1
      ;;
  esac
else
  TARGET_SCHEMES=("Controlled" "Controller")
fi

mkdir -p "$BUILD_DIR"

cd "$ROOT_DIR"
if ! command -v swift >/dev/null 2>&1; then
  echo "swift command not found. Install Xcode / Swift toolchain." >&2
  exit 1
fi

# Ensure required tools
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install Xcode." >&2
  exit 1
fi
if ! command -v lipo >/dev/null 2>&1; then
  echo "lipo not found. It should come with Xcode command line tools." >&2
  exit 1
fi

# Build for each scheme
for scheme in "${TARGET_SCHEMES[@]}"; do
  echo "\n[*] Building scheme: $scheme"

  echo "- Building arm64..."
  rm -rf "$ARM_DERIVED"
  if xcodebuild -scheme "$scheme" -configuration Release -derivedDataPath "$ARM_DERIVED" -package-path "$ROOT_DIR" -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES ENABLE_BITCODE=NO build; then
    echo "  -> arm64 build succeeded"
  else
    echo "  -> arm64 build failed" >&2
    echo "Aborting: arm64 build required to create universal binary." >&2
    exit 1
  fi

  echo "- Building x86_64..."
  rm -rf "$X86_DERIVED"
  if xcodebuild -scheme "$scheme" -configuration Release -derivedDataPath "$X86_DERIVED" -package-path "$ROOT_DIR" -destination 'platform=macOS,arch=x86_64' CODE_SIGNING_ALLOWED=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES ENABLE_BITCODE=NO build; then
    echo "  -> x86_64 build succeeded"
  else
    echo "  -> x86_64 build failed. If you're on Apple Silicon without Rosetta, this may be expected." >&2
    echo "  -> Continuing to produce an arm64-only binary." >&2
  fi

  # Find built product binaries
  ARM_BIN_PATH="$(find "$ARM_DERIVED/Build/Products/Release" -type f -name "$scheme" -print -quit || true)"
  X86_BIN_PATH="$(find "$X86_DERIVED/Build/Products/Release" -type f -name "$scheme" -print -quit || true)"

  mkdir -p "$UNIVERSAL_DIR"
  OUTPUT_PATH="$UNIVERSAL_DIR/$scheme"

  if [[ -n "$ARM_BIN_PATH" && -n "$X86_BIN_PATH" ]]; then
    echo "- Creating universal binary: $OUTPUT_PATH"
    lipo -create -output "$OUTPUT_PATH" "$ARM_BIN_PATH" "$X86_BIN_PATH"
    chmod +x "$OUTPUT_PATH"
    echo "  -> Created universal binary: $OUTPUT_PATH"
  elif [[ -n "$ARM_BIN_PATH" && -z "$X86_BIN_PATH" ]]; then
    echo "- Only arm64 binary available. Copying arm64 binary to: $OUTPUT_PATH"
    cp "$ARM_BIN_PATH" "$OUTPUT_PATH"
    chmod +x "$OUTPUT_PATH"
    echo "  -> arm64-only binary available at: $OUTPUT_PATH"
  elif [[ -z "$ARM_BIN_PATH" && -n "$X86_BIN_PATH" ]]; then
    echo "- Only x86_64 binary available. Copying x86_64 binary to: $OUTPUT_PATH"
    cp "$X86_BIN_PATH" "$OUTPUT_PATH"
    chmod +x "$OUTPUT_PATH"
    echo "  -> x86_64-only binary available at: $OUTPUT_PATH"
  else
    echo "[!] Could not find built binaries for scheme $scheme" >&2
  fi
done

echo "\n[*] All done. Universal binaries (or architecture-specific fallbacks) are in: $UNIVERSAL_DIR"
echo "To run the controlled server: $UNIVERSAL_DIR/Controlled"
echo "To run the controller client: $UNIVERSAL_DIR/Controller"

echo "Script finished."
