# Finder Click Fix for macOS

Clicking an inactive Finder window while moving the mouse even slightly can leave it in the background. This tiny menu bar app brings the clicked window to the front.

[Download (Apple Silicon)](https://github.com/cocm/finder-click-fix/releases/latest) · under 300 KB

Requires macOS 13 or later. Open the DMG and drag the app to Applications. Launch it and allow Accessibility in System Settings. Quit from the menu bar.

Desktop, dialogs, and sheets are excluded.

## License

[MIT](LICENSE)

<details>
<summary>Developers</summary>

### Build

Requires Xcode Command Line Tools and your own Developer ID Application certificate.
Find its SHA-1 with `security find-identity -v -p codesigning`:

```sh
export SIGNING_IDENTITY="YOUR_CERTIFICATE_SHA1"
sh build.sh
```

Installs to `/Applications/Finder Click Fix.app`. If `SIGNING_IDENTITY` is unset, the script uses its default certificate.

### DMG

```sh
sh build.sh --dmg
```

Creates a signed, unnotarized DMG in `dist/`. For notarization, store your credentials in Keychain once using your Apple Developer Team ID:

```sh
xcrun notarytool store-credentials finder-click-fix --team-id "YOUR_TEAM_ID"
sh build.sh --dmg finder-click-fix
```

### Tests

```sh
sh test.sh
```

Regression tests use simulated Accessibility and input events. Actual clicks, drags, and permission recovery need testing on a Mac.

</details>
