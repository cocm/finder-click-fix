# Finder Click Fix

Finderのウィンドウをクリックしたとき、先にFinderをアクティブにする小さなメニューバーアプリ。

macOS 13以降。起動後、システム設定でアクセシビリティを許可してください。終了はメニューバーから。
デスクトップ・ダイアログ・シートは対象外です。

## ビルド

Xcode Command Line Toolsと、`build.sh`で指定したDeveloper ID署名証明書が必要です。

```sh
sh build.sh
```

`/Applications/Finder Click Fix.app`に設置します。

## テスト

```sh
sh test.sh
```

AXと入力を模擬した回帰テストです。実際のクリック・ドラッグ・権限復旧は実機確認が必要です。

## ライセンス

[MIT](LICENSE)
