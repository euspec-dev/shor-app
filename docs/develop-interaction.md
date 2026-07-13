# 現像インタラクション（長押し）

scr-view画面で、ブラウザ写真のポラロイドを「現像」するための長押し操作の
実装。コードは[shor.html:865-947](../shor.html#L865-L947)にまとまっている。
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

`resetDevelop(hard)`（[shor.html:871-880](../shor.html#L871-L880)）が
これらを初期状態に戻す。`hard=true`は新しい写真を開いたとき
（`openView()`内）、`hard=false`は現像未完了のまま指を離したときに使う
（`hard=false`では下部の案内テキストは消さない）。

## 押している間: `tick(now)`

`DEVELOP_MS = 5000`（[shor.html:595](../shor.html#L595)）で正規化した
進捗`t`（0〜1）から、`e = 1 - (1-t)^2`という減速イージングを作り、
写真のぼかしと粒度を滑らかに解いていく（[shor.html:882-897](../shor.html#L882-L897)）。

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

案内文（`#under-note`）は`min-height:3.9em`（[shor.html:298](../shor.html#L298)）を
持たせてあり、表示/非表示で本文の高さが変わらないようにしている。この文言は
`<br>`で強制的に2行になるため、以前`min-height`が2行分に足りておらず、
文言が出た瞬間にscr-view全体の位置がわずかにずれるバグがあった（修正済み）。

`t < 1`の間は`requestAnimationFrame`で自分自身を呼び続ける
（`pressing`が`false`になった時点で自然に止まる）。

## 押し始め: `pointerdown`

`zone.setPointerCapture(e.pointerId)`（[shor.html:902](../shor.html#L902)）
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
   （[shor.html:922-926](../shor.html#L922-L926)。UIのwash演出はこれを
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

`shor.html`全体で長押しメニュー・選択・ドラッグ保存を無効化している。
CSS側（[shor.html:46-55](../shor.html#L46-L55)）で
`user-select`/`touch-callout`/`user-drag`等を`none`にし、その上でJS側
（[shor.html:718-719](../shor.html#L718-L719)、`contextmenu`/`selectstart`/
`dragstart`の`preventDefault`）が「最終防衛線」として二重に無効化している。
これは現像ゾーンの長押しがOS標準のコンテキストメニューやテキスト選択と
衝突しないようにするための、アプリ全体にかかる前提。
