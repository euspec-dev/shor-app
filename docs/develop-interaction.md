# 現像インタラクション（長押し）

scr-view画面で、ブラウザ写真のポラロイドを「現像」するための長押し操作の
実装。コードは[shor.html:682-773](../shor.html#L682-L773)にまとまっている。
枠の消費・サーバ側の予約タイミングとの関係は[view-grants.md](view-grants.md)・
[distribution.md](distribution.md)を参照。ここでは操作そのものの状態遷移を扱う。

## 状態変数

| 変数 | 意味 |
|---|---|
| `pressing` | 現在指を置いているか |
| `t0` | 押し始めた時刻（`performance.now()`） |
| `developed` | このポラロイドの現像が完了したか（1枚につき1回だけ`true`になる） |
| `leaving` | wash演出で画面遷移中（この間は新たな押下を無視する） |
| `confirmPromise` | 現像完了時に発火した`confirmDrift()`のPromise（`release()`が待ち合わせに使う） |
| `noteTimer` | 「離すのが早すぎる」ナグメッセージの自動非表示タイマー |

`resetDevelop(hard)`（[shor.html:688-697](../shor.html#L688-L697)）が
これらを初期状態に戻す。`hard=true`は新しい写真を開いたとき
（`openView()`内）、`hard=false`は現像未完了のまま指を離したときに使う
（`hard=false`では下部の案内テキストは消さない）。

## 押している間: `tick(now)`

`DEVELOP_MS = 5000`（[shor.html:427](../shor.html#L427)）で正規化した
進捗`t`（0〜1）から、`e = 1 - (1-t)^2`という減速イージングを作り、
写真のぼかしと粒度を滑らかに解いていく（[shor.html:699-713](../shor.html#L699-L713)）。

```
blur      : 26px → 0px          (26 * (1 - e))
saturate  : 0.92 → 1.0          (.92 + .08 * e)
frost透明度: 1   → 0            (1 - e)
```

`t >= 1`に達した瞬間（1回だけ、`!developed`ガード）:
- `developed = true`
- `consumeView()`（閲覧枠の消費、[view-grants.md](view-grants.md)）
- `confirmDrift(currentPostId)`をfire-and-forgetで呼び、`confirmPromise`に保持
- 現像完了ラベルの表示切り替え、「写真が現像されました。指を離すと写真は
  見られなくなります。」という案内を表示

`t < 1`の間は`requestAnimationFrame`で自分自身を呼び続ける
（`pressing`が`false`になった時点で自然に止まる）。

## 押し始め: `pointerdown`

`zone.setPointerCapture(e.pointerId)`（[shor.html:719](../shor.html#L719)）
でポインタをキャプチャし、指がゾーンの外に出てもイベントを取り続けられる
ようにしている（＝押している間にスクロール等で指がずれても`pointerup`を
確実に拾える）。`leaving`中（wash演出中）は新しい押下を無視する。

## 離した時: `release()`（`pointerup` / `pointercancel`共通）

保持秒数`heldSec`を計算し、`heldTotalSec`に加算する（同じ写真に対して
複数回押し直した場合も合算される）。

### 現像完了していた場合（`developed === true`）

1. `leaving = true`にして以降の押下を無視
2. `confirmPromise`の完了を待ってから`recordViewHistoryDB()`で
   `viewed_seconds`を確定更新する非同期処理を(待たずに)開始する
   （[shor.html:739-743](../shor.html#L739-L743)。UIのwash演出はこれを
   待たずに即座に始まる — 詳細は[distribution.md](distribution.md)の
   「peek → confirm」節）
3. ポラロイドに`washed`クラス、案内文に`fading`クラスを付けてフェードアウト
4. 1500ms後、要素をリセットして次の画面へ:
   `viewOrigin === "done"` なら`backToDone()`、それ以外は`openPost()`

### 現像未完了のまま離した場合（`developed === false`）

`resetDevelop(false)`で見た目を巻き戻し、「現像するには指を置いたままに
してください」と表示（3000msで自動的に消える）。**画面は遷移せず、
同じ写真のまま**再度長押しに挑戦できる（枠もサーバ予約もまだ何も
消費されていないため、やり直しは何度でも自由 — [view-grants.md](view-grants.md)参照）。

## タッチ操作全般の制約

`shor.html`全体で長押しメニュー・選択・ドラッグ保存を無効化している
（[shor.html:34-44](../shor.html#L34-L44)、`contextmenu`/`selectstart`/
`dragstart`の`preventDefault`）。これは現像ゾーンの長押しがOS標準の
コンテキストメニューやテキスト選択と衝突しないようにするための、
アプリ全体にかかる前提。
