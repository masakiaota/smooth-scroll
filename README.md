# SmoothScroll

マウスホイールによる縦横スクロールを滑らかにする、自分用のmacOSメニューバーアプリ。現在のmacOSとApple Silicon向けに構築する。外部ライブラリは不要。

## 使う

1. `/Applications/SmoothScroll.app`を開く。初回は準備画面の各「許可をリクエスト」を押し、macOSの案内に従って許可する。確認画面が出ない場合は、同じボタンが「設定を開く」に変わるので、そこからSmoothScrollをオンにする。戻ると状態は自動で更新される。準備が整えば「開始する」、送信許可の反映待ちなら「再起動して開始」を押す。後者は同じ場所のアプリを開き直し、許可を確認して自動で開始する。設定でオンでも未許可表示のままの場合は、画面下の再起動ボタンを使う。再起動後も未許可なら自動開始せず、準備画面に戻る。一時署名の不一致は別途、下記の復旧手順が必要になる。
2. メニューバーのホイールアイコンが起動中の目印。Dockには表示しない。
3. 「設定…」で平滑化しないアプリを追加、削除する。変更は即時反映し、自動保存する。
4. 「終了」で平滑化を止める。設定ウィンドウを閉じても動作は続く。

PreviewとPowerPointは初期状態で除外する。アプリ全体が除外対象となるため、Previewの連続表示も元の挙動になる。除外を削除した選択も保持する。

「ログイン時に起動」は初回起動で登録する。設定画面で解除できる。macOS側の承認待ちや登録失敗は設定画面に表示する。システム設定で無効にした選択を毎回上書きしない。
ログイン起動を使う場合は、アプリを置く場所を決めてから起動する。移動する際はログイン起動を一度解除し、旧アプリを終了して移動後のアプリで再登録する。

## 構築、更新

Xcode Command Line Toolsが必要。リポジトリのルートで実行する。

```sh
make app SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
open SmoothScroll.app
```

ルートに指定した証明書で署名済みのアプリができる。署名指定を省略すると、既存のアプリを変更する前に停止する。更新時は、実行中のSmoothScrollをメニューから終了してから構築する。古いコピーを同時に起動しない。
更新を通じて同じ署名元とバンドルIDを維持する。証明書がない検証環境でのみ、`make app SIGN_IDENTITY=-` により一時署名を明示できる。一時署名では内容の変更により以前の許可との対応が崩れ、システム設定がオンでも権限が拒否される場合がある。

### 一時署名で権限が一致しなくなった場合

SmoothScrollを終了し、次を実行する。他のアプリの権限やSmoothScrollの設定は変更しない。

```sh
tccutil reset Accessibility com.masakiaota.smooth-scroll
tccutil reset ListenEvent com.masakiaota.smooth-scroll
open /Applications/SmoothScroll.app
```

準備画面から両方の許可を要求し、macOS側で許可する。復旧確認までは再ビルドや再署名をしない。一時署名から証明書による署名へ移行するときも、再許可が必要になる場合がある。

### 証明書を持つMacで署名する

Developer Programへの加入だけでは署名できない。そのMacのキーチェーンに証明書と対応する秘密鍵が必要。

```sh
security find-identity -v -p codesigning
make app SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
```

証明書名の代わりに一覧のSHA-1も指定できる。指定した署名に失敗した場合はビルドを失敗させ、アドホック署名へ自動で切り替えない。証明書や秘密鍵はGitへ入れない。
証明書を指定した構築ではHardened Runtimeとタイムスタンプを有効にする。公証は行わない。別Macへのコピー時は権限の許可が必要で、起動可否はGatekeeperと端末管理にも依存する。

## 検証と構成

```sh
make test
```

平滑化の収束、方向反転、設定の保存と重複防止、残量破棄を自己検証する。テストは独立した一時設定領域を使用し、入力監視やログイン項目の登録は行わない。実際の滑らかさとページ送りは利用者が確認する。

- `main.swift`：平滑化、ポインタ下のアプリ判定、メニューバー、権限処理。
- `Settings.swift`：除外一覧、設定画面、ログイン項目。
- `scripts/icons.swift`：採用した形からアプリとメニュー用画像を生成。
- `assets/design-reference.svg`：採用デザインの参照図。
- `Info.plist`、`Makefile`：アプリ定義と構築。

設定はUserDefaultsの`com.masakiaota.smooth-scroll`に保存する。`excludedApps`が除外一覧、`loginInitialized`が初回登録の実施記録。ログイン項目の現在状態はmacOSから取得する。
アプリと中間生成物はGit管理しない。GitHubへ公開する際もソースだけから再構築できる。

## 処理上の境界

位相のないホイール入力を120 Hzで分割する。位相付きのネイティブ入力は通す。対象はポインタ下の通常ウィンドウで判定し、判定できない対象には元の入力を通す。
送信中に対象アプリが変わる、除外対象になる、ネイティブ入力が入る場合は残量を破棄する。出力イベントの座標は上書きせず、システムのイベント経路へ送る。送信権限を確認できない場合は元の入力を通す。特殊なウィンドウ構成では平滑化されない場合がある。

ログイン項目はAppleの[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)を使う。
