#!/bin/sh
set -eu
cd "$(dirname "$0")"
# Developer ID Application: Keita Matsubara (7L8SQDRWQK)
signing_identity="64EFA51E321B79D5E74160BAD9206B7D827E6E12"
if ! security find-identity -v -p codesigning | grep -Fq " $signing_identity "; then
    printf '%s\n' 'Developer ID署名証明書が見つかりません。ビルドを中止します。' >&2
    exit 1
fi
app_path="dist/Finder Click Fix.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp Info.plist "$app_path/Contents/Info.plist"
cp assets/StatusIcon.png assets/StatusIcon@2x.png assets/AppIcon.icns "$app_path/Contents/Resources/"
rm -f "$app_path/Contents/Resources/StatusIcon.pdf"
xcrun clang -std=c17 -fobjc-arc -Oz -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    main.m -framework AppKit -framework ApplicationServices -framework CoreFoundation \
    -o "$app_path/Contents/MacOS/FinderClickFix"
codesign --force --sign "$signing_identity" --timestamp "$app_path"
codesign --verify --strict "$app_path"
install_path="/Applications/Finder Click Fix.app"
rm -rf "$install_path"
ditto "$app_path" "$install_path"
codesign --verify --strict "$install_path"
printf '%s\n' "$install_path"
