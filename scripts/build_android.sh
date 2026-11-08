#!/usr/bin/env bash
# Builds Infinite Drive for Android from the command line, without the Godot editor.
#
#   scripts/build_android.sh              # tests + debug APK into build/
#   SKIP_TESTS=1 scripts/build_android.sh # APK only
#   BUILD_TYPE=release scripts/build_android.sh   # signed release AAB (needs keystore env vars)
#
# Steps: locate or download Godot and its export templates, configure the Android SDK and
# JDK for the export, create a local debug keystore (outside the repository), import the
# project, run the automated tests, export the APK, and verify it with the SDK tools.
#
# Environment (all optional unless noted):
#   GODOT_BIN       path to a Godot 4.x executable (otherwise downloaded into .tools/)
#   GODOT_VERSION   Godot release to use (default 4.6.1)
#   ANDROID_HOME    Android SDK root (required; default /opt/android-sdk if present)
#   JAVA_HOME       JDK 17+ (default: derived from javac on PATH)
#   SKIP_TESTS=1    skip the headless test suite
#   BUILD_TYPE      debug (default) or release
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD   for release builds (never stored in git)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME="$ROOT/game"
BUILD="$ROOT/build"
TOOLS="$ROOT/.tools"
GODOT_VERSION="${GODOT_VERSION:-4.6.1}"
BUILD_TYPE="${BUILD_TYPE:-debug}"
RELEASE_TAG="${GODOT_VERSION}-stable"
RELEASE_BASE="https://github.com/godotengine/godot-builds/releases/download/${RELEASE_TAG}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- Godot binary
find_godot() {
	if [[ -n "${GODOT_BIN:-}" ]]; then
		[[ -x "$GODOT_BIN" ]] || die "GODOT_BIN is not executable: $GODOT_BIN"
		echo "$GODOT_BIN"
		return
	fi
	local dir="$TOOLS/godot-$GODOT_VERSION"
	local bin="$dir/Godot_v${RELEASE_TAG}_linux.x86_64"
	if [[ ! -x "$bin" ]]; then
		log "Downloading Godot $GODOT_VERSION"
		mkdir -p "$dir"
		curl -fsSL -o "$dir/godot.zip" "$RELEASE_BASE/Godot_v${RELEASE_TAG}_linux.x86_64.zip"
		unzip -o -q "$dir/godot.zip" -d "$dir"
		chmod +x "$bin"
	fi
	echo "$bin"
}

# ---------------------------------------------------------------- export templates
ensure_templates() {
	local dest="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}.stable"
	if [[ -f "$dest/android_debug.apk" && -f "$dest/android_release.apk" ]]; then
		return
	fi
	log "Installing export templates for Godot $GODOT_VERSION (large download)"
	mkdir -p "$dest" "$TOOLS"
	curl -fsSL -o "$TOOLS/templates-$GODOT_VERSION.tpz" "$RELEASE_BASE/Godot_v${RELEASE_TAG}_export_templates.tpz"
	local extract="$TOOLS/templates-extract"
	rm -rf "$extract"
	unzip -q "$TOOLS/templates-$GODOT_VERSION.tpz" -d "$extract"
	mv "$extract/templates/"* "$dest/"
	rm -rf "$extract"
}

# ---------------------------------------------------------------- Android SDK and JDK
resolve_android_sdk() {
	local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
	if [[ -z "$sdk" && -d /opt/android-sdk ]]; then
		sdk=/opt/android-sdk
	fi
	[[ -n "$sdk" && -d "$sdk" ]] || die "Android SDK not found. Set ANDROID_HOME (platform, build-tools 36 and platform-tools are needed)."
	echo "$sdk"
}

resolve_java() {
	if [[ -n "${JAVA_HOME:-}" ]]; then
		echo "$JAVA_HOME"
		return
	fi
	local javac
	javac="$(command -v javac || true)"
	[[ -n "$javac" ]] || die "No JDK found. Install JDK 17+ or set JAVA_HOME."
	dirname "$(dirname "$(readlink -f "$javac")")"
}

write_editor_settings() {
	local sdk="$1" java="$2" keystore="$3"
	local cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
	mkdir -p "$cfg_dir"
	cat > "$cfg_dir/editor_settings-${GODOT_VERSION%.*}.tres" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$sdk"
export/android/java_sdk_path = "$java"
export/android/debug_keystore = "$keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF
}

ensure_debug_keystore() {
	local keystore="$HOME/.android/debug.keystore"
	if [[ ! -f "$keystore" ]]; then
		log "Creating local debug keystore (not part of the repository)"
		mkdir -p "$(dirname "$keystore")"
		keytool -genkeypair -v -keystore "$keystore" -storepass android -alias androiddebugkey \
			-keypass android -keyalg RSA -keysize 2048 -validity 10000 \
			-dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1 || die "keytool failed"
	fi
	echo "$keystore"
}

# ---------------------------------------------------------------- main
GODOT="$(find_godot)"
ensure_templates
SDK="$(resolve_android_sdk)"
JAVA="$(resolve_java)"
KEYSTORE="$(ensure_debug_keystore)"
write_editor_settings "$SDK" "$JAVA" "$KEYSTORE"
export ANDROID_HOME="$SDK"
BUILD_TOOLS="$(ls -d "$SDK"/build-tools/* | sort -V | tail -n 1)"

log "Godot: $("$GODOT" --version 2>/dev/null | head -n 1)"
log "Android SDK: $SDK (build-tools $(basename "$BUILD_TOOLS")), JDK: $JAVA"

log "Importing project"
"$GODOT" --headless --path "$GAME" --import >/dev/null 2>&1 || true

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
	log "Running automated tests"
	set +e
	"$GODOT" --headless --path "$GAME" -s res://testing/run_tests.gd
	status=$?
	set -e
	[[ $status -eq 0 ]] || die "tests failed (exit $status)"
fi

mkdir -p "$BUILD"
if [[ "$BUILD_TYPE" == "release" ]]; then
	OUT="$BUILD/InfiniteDrive-release.aab"
	log "Exporting signed release bundle"
	"$GODOT" --headless --path "$GAME" --export-release "Android Release" "$OUT"
else
	OUT="$BUILD/InfiniteDrive-debug.apk"
	log "Exporting debug APK"
	"$GODOT" --headless --path "$GAME" --export-debug "Android Debug" "$OUT"
fi
[[ -s "$OUT" ]] || die "export produced no file: $OUT"

log "Verifying $(basename "$OUT")"
if [[ "$OUT" == *.apk ]]; then
	"$BUILD_TOOLS/aapt2" dump badging "$OUT" | grep -E "^package|sdkVersion|targetSdkVersion|launchable-activity|supports-screens" || true
	listing="$BUILD/apk-listing.txt"
	unzip -Z1 "$OUT" > "$listing"
	grep -qx "lib/arm64-v8a/libgodot_android.so" "$listing" || die "APK has no arm64-v8a native library"
	rm -f "$listing"
	"$BUILD_TOOLS/zipalign" -c -p 4 "$OUT" && echo "zipalign: OK"
	"$BUILD_TOOLS/apksigner" verify --print-certs "$OUT" | grep -E "Verifies|Signer #1 certificate DN" || die "APK signature check failed"
	rm -f "$OUT.idsig"
fi
sha256sum "$OUT"
log "Done: $OUT"
