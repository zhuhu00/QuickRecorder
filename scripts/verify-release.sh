#!/bin/zsh

set -eu

app_path="${1:-build/Build/Products/Release/QuickRecorder.app}"
binary_path="$app_path/Contents/MacOS/QuickRecorder"
info_plist="$app_path/Contents/Info.plist"

fail() {
    print -u2 -- "Release verification failed: $1"
    exit 1
}

require_equal() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    [[ "$actual" == "$expected" ]] || fail "$label is '$actual', expected '$expected'"
}

require_contains() {
    local value="$1"
    local expected="$2"
    local label="$3"
    [[ "$value" == *"$expected"* ]] || fail "$label does not contain '$expected'"
}

[[ -d "$app_path" ]] || fail "app not found at $app_path"
[[ -x "$binary_path" ]] || fail "executable not found at $binary_path"

architectures="$(lipo -archs "$binary_path")"
require_equal "$architectures" "arm64" "architectures"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
minimum_system="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
require_equal "$bundle_id" "io.github.zhuhu00.QuickRecorder" "bundle identifier"
require_equal "$minimum_system" "14.2" "minimum system version"

codesign --verify --deep --strict "$app_path" || fail "codesign verification failed"
signature="$(codesign -dv --verbose=4 "$app_path" 2>&1)"
require_contains "$signature" "Authority=Apple Development:" "signing authority"
require_contains "$signature" "TeamIdentifier=H7W4RZVP64" "team identifier"
require_contains "$signature" "Runtime Version=" "hardened runtime"

entitlements="$(codesign -d --entitlements :- "$app_path" 2>/dev/null)"
audio_input="$(print -r -- "$entitlements" | xmllint --xpath 'boolean(/plist/dict/key[.="com.apple.security.device.audio-input"]/following-sibling::*[1][self::true])' - 2>/dev/null)"
camera="$(print -r -- "$entitlements" | xmllint --xpath 'boolean(/plist/dict/key[.="com.apple.security.device.camera"]/following-sibling::*[1][self::true])' - 2>/dev/null)"
require_equal "$audio_input" "true" "audio-input entitlement"
require_equal "$camera" "true" "camera entitlement"

get_task_allow="$(print -r -- "$entitlements" | xmllint --xpath 'boolean(/plist/dict/key[.="com.apple.security.get-task-allow"])' - 2>/dev/null)"
if [[ "$get_task_allow" == true ]]; then
    fail "Release contains com.apple.security.get-task-allow"
fi

[[ -f "$app_path/Contents/Resources/LICENSE" ]] || fail "GNU AGPL license is missing from the app bundle"
[[ -f "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md" ]] || fail "third-party notices are missing from the app bundle"

set +e
gatekeeper_output="$(spctl -a -vv --type execute "$app_path" 2>&1)"
gatekeeper_status=$?
set -e
(( gatekeeper_status != 0 )) || fail "Gatekeeper unexpectedly accepted this non-notarized Apple Development build"

print -- "Release verification passed"
print -- "  Version: $version ($build_number)"
print -- "  Architecture: $architectures"
print -- "  Minimum macOS: $minimum_system"
print -- "  Bundle ID: $bundle_id"
print -- "  Team: H7W4RZVP64"
print -- "  Gatekeeper: rejected as expected for the current informal distribution model"
print -- "$gatekeeper_output"
