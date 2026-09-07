# SmoothScroll

位相情報を持たないマウスホイール入力を小数ピクセルへ分割し、滑らかにするmacOSアプリである。
縦ホイールと横ホイールを処理し、Magic Mouseやトラックパッドなどの位相付き入力は変更しない。

## 構築

```sh
cd /Users/masakiaota/Documents/GitHub/smooth-scroll-mvp
make app
```

完成した`SmoothScroll.app`をFinderから開く。Dockに表示されている間だけ平滑化が有効になる。
終了するには`Command + Q`を押すか、Dockから終了する。

初回起動時は「システム設定 > プライバシーとセキュリティ」で、
SmoothScrollに「入力監視」と「アクセシビリティ」を許可してから起動し直す。

同じmacOS版とApple Siliconを使用するMacであれば、`SmoothScroll.app`をコピーして利用できる。
権限はコピー先のMacで改めて許可する。

## 自己検証

```sh
make test
```
