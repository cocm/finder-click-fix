#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ "$#" -gt 2 ] || { [ "$#" -gt 0 ] && [ "$1" != "--dmg" ]; } ||
    { [ "$#" -eq 2 ] && [ -z "$2" ]; }; then
    printf '%s\n' 'Usage: sh build.sh [--dmg [keychain-profile]]' >&2
    exit 2
fi
# Developer ID Application: Keita Matsubara (7L8SQDRWQK)
signing_identity="${SIGNING_IDENTITY:-64EFA51E321B79D5E74160BAD9206B7D827E6E12}"
if ! security find-identity -v -p codesigning | grep -Fq " $signing_identity "; then
    printf '%s\n' 'Developer ID署名証明書が見つかりません。ビルドを中止します。' >&2
    exit 1
fi
app_path="dist/Finder Click Fix.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp Info.plist "$app_path/Contents/Info.plist"
cp assets/StatusIcon.png assets/StatusIcon@2x.png assets/AppIcon.icns "$app_path/Contents/Resources/"
cp LICENSE "$app_path/Contents/Resources/"
rm -f "$app_path/Contents/Resources/StatusIcon.pdf"
xcrun clang -std=c17 -fobjc-arc -Oz -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    main.m -framework AppKit -framework ApplicationServices -framework CoreFoundation -framework ServiceManagement \
    -o "$app_path/Contents/MacOS/FinderClickFix"
codesign --force --sign "$signing_identity" --options runtime --timestamp "$app_path"
codesign --verify --strict "$app_path"
install_path="/Applications/Finder Click Fix.app"
rm -rf "$install_path"
ditto "$app_path" "$install_path"
codesign --verify --strict "$install_path"
printf '%s\n' "$install_path"

if [ "$#" -eq 0 ]; then exit 0; fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
architecture="$(lipo -archs "$app_path/Contents/MacOS/FinderClickFix")"
dmg_path="dist/Finder-Click-Fix-$version-$architecture.dmg"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/finder-click-fix-dmg.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT HUP INT TERM
ditto "$app_path" "$stage_dir/Finder Click Fix.app"
ln -s /Applications "$stage_dir/Applications"
hdiutil create -volname 'Finder Click Fix' -srcfolder "$stage_dir" -format UDZO -ov "$dmg_path"
codesign --force --sign "$signing_identity" --timestamp "$dmg_path"
codesign --verify --strict "$dmg_path"
if [ "$#" -eq 1 ]; then
    printf '署名済みDMG（未公証）: %s\n' "$dmg_path"
    exit 0
fi

submission_path="${dmg_path%.dmg}.notary.json"
log_path="${dmg_path%.dmg}.notary-log.json"
xcrun notarytool submit "$dmg_path" --keychain-profile "$2" --wait --timeout 10m \
    --output-format json > "$submission_path"
submission_id="$(plutil -extract id raw -o - "$submission_path")"
status="$(plutil -extract status raw -o - "$submission_path")"
xcrun notarytool log "$submission_id" --keychain-profile "$2" "$log_path"
if [ "$status" != 'Accepted' ]; then
    printf '公証失敗: %s（%s）\n' "$status" "$log_path" >&2
    exit 1
fi
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose "$dmg_path"
printf '公証済みDMG: %s\n' "$dmg_path"
