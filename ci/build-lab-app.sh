#!/usr/bin/env bash
# The project root is the pinned Solipsism v9.3.1 checkout, not a production Android device.
set -Eeuo pipefail
export LC_ALL=C
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$root"
base=ff82344988b3e783feddedaeb01d913c945fca85
git merge-base --is-ancestor "$base" HEAD || { echo 'ERROR: Solipsism pinned base is not an ancestor' >&2; exit 2; }
git diff --quiet "$base" HEAD -- app || { echo 'ERROR: Solipsism app source deviates from pinned base' >&2; exit 2; }
patch_file=patches/sa-antares-only-v931-20261015.patch
printf '8d50f519e2ab7e970b07c0fedba65de28fba0e8db7ef5c82a8ba65b22b835fcc  %s\n' "$patch_file" | sha256sum --check --status
[[ -s "$root/native-engine/target/aarch64-linux-android/checked-release/servoapp.apk" ]] || { echo 'ERROR: native build APK missing' >&2; exit 3; }
lib_dir="$root/app/src/main/jniLibs/arm64-v8a"
[[ ! -L "$lib_dir" && -f "$lib_dir/libservoshell.so" && ! -L "$lib_dir/libservoshell.so" ]] || { echo 'ERROR: unsafe library path' >&2; exit 4; }
mkdir -p "$root/build-evidence"
unzip -p "$root/native-engine/target/aarch64-linux-android/checked-release/servoapp.apk" 'lib/arm64-v8a/libservoshell.so' > "$root/build-evidence/libservoshell.so"
[[ -s "$root/build-evidence/libservoshell.so" ]] || { echo 'ERROR: native library missing in engine APK' >&2; exit 5; }
readelf -h "$root/build-evidence/libservoshell.so" | grep -q 'Machine:.*AArch64' || { echo 'ERROR: wrong native ABI' >&2; exit 5; }
# Only touch files in isolated build checkout; no installation or data cleanup.
git apply --check "$patch_file"
git apply "$patch_file"
cp -- "$root/build-evidence/libservoshell.so" "$lib_dir/libservoshell.so"
sha256sum "$root/build-evidence/libservoshell.so" "$lib_dir/libservoshell.so" > "$root/build-evidence/native-hashes.txt"
./gradlew --no-daemon :app:testSolipsismBrowserDebugUnitTest :app:assembleSolipsismBrowserDebug
apk=$(find app/build/outputs/apk -type f -name '*debug*.apk' -print -quit)
[[ -n "$apk" && -s "$apk" ]] || { echo 'ERROR: debug APK absent' >&2; exit 6; }
unzip -p "$apk" 'lib/arm64-v8a/libservoshell.so' | sha256sum | awk '{print $1}' > "$root/build-evidence/apk-lib.sha256"
sha256sum "$root/build-evidence/libservoshell.so" | awk '{print $1}' > "$root/build-evidence/source-lib.sha256"
cmp -s "$root/build-evidence/apk-lib.sha256" "$root/build-evidence/source-lib.sha256" || { echo 'ERROR: final APK does not contain the new Servo lib' >&2; exit 7; }
# Query an Android SDK aapt executable, not the final APK's untrusted self-report.
aapt_exe=$(find "${ANDROID_HOME:?ANDROID_HOME required}/build-tools" -type f -name aapt -print | sort -r | head -n 1)
[[ -x "$aapt_exe" ]] || { echo 'ERROR: Android aapt unavailable' >&2; exit 8; }
"$aapt_exe" dump badging "$apk" | grep -q "package: name='com.krystelligence.solipsism.antareslab'" || { echo 'ERROR: isolated debug application ID not present' >&2; exit 8; }
cp -- "$apk" "$root/build-evidence/solipsism-antares-only-lab.apk"
sha256sum "$root/build-evidence/solipsism-antares-only-lab.apk" > "$root/build-evidence/lab-apk.sha256"
printf 'Source compilation and native binary identity verified. Device runtime NOT VERIFIED.\n'
