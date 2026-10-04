# Finder Click Fix

Finderのウィンドウをクリックしたとき、先にFinderをアクティブにする小さなメニューバーアプリ。

[ダウンロード（Apple Silicon）](https://github.com/cocm/finder-click-fix/releases/latest)。DMGを開き、アプリをApplicationsフォルダへコピーしてください。

macOS 13以降。起動後、システム設定でアクセシビリティを許可してください。終了はメニューバーから。
デスクトップ・ダイアログ・シートは対象外です。

## ライセンス

[MIT](LICENSE)

<details>
<summary>開発者向け</summary>

### ビルド

Xcode Command Line Toolsと、自分のDeveloper ID Application署名証明書が必要です。
`security find-identity -v -p codesigning`で証明書のSHA-1を確認し、指定します。

```sh
export SIGNING_IDENTITY="証明書のSHA-1"
sh build.sh
```

`/Applications/Finder Click Fix.app`に設置します。証明書の指定を省略すると、`build.sh`の既定値を使います。

### DMG

```sh
sh build.sh --dmg
```

署名済み・未公証のDMGを`dist/`に生成します。公証する場合は、自分のApple DeveloperのTeam IDで認証をKeychainへ一度登録します。

```sh
xcrun notarytool store-credentials finder-click-fix --team-id "自分のTeam ID"
sh build.sh --dmg finder-click-fix
```

### テスト

```sh
sh test.sh
```

AXと入力を模擬した回帰テストです。実際のクリック・ドラッグ・権限復旧は実機確認が必要です。

</details>
