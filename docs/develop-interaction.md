# 現像インタラクション（長押し）

scr-view画面で、ブラウザ写真のポラロイドを「現像」するための長押し操作の
実装。コードは[shor.html:1346-1433](../shor.html#L1346-L1433)にまとまっている。
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

`resetDevelop(hard)`（[shor.html:1352-1361](../shor.html#L1352-L1361)）が
これらを初期状態に戻す。`hard=true`は新しい写真を開いたとき
（`openView()`内）、`hard=false`は現像未完了のまま指を離したときに使う
（`hard=false`では下部の案内テキストは消さない）。

## 押している間: `tick(now)`

`DEVELOP_MS = 5000`（[shor.html:931](../shor.html#L931)）で正規化した
進捗`t`（0〜1）から、`e = 1 - (1-t)^2`という減速イージングを作り、
写真のぼかしと粒度を滑らかに解いていく（`tick(now)`、[shor.html:1363-1378](../shor.html#L1363-L1378)）。

```
blur      : 26px → 0px          (26 * (1 - e))
saturate  : 0.92 → 1.0          (.92 + .08 * e)
frost透明度: 1   → 0            (1 - e)
```

`t >= 1`に達した瞬間（1回だけ、`!developed`ガード）:
- `developed = true`
- `consumeView()`（閲覧枠の消費、[view-grants.md](view-grants.md)）
- `confirmDrift(currentPostId)`をfire-and-forgetで呼び、`confirmPromise`に保持
- 現像完了ラベルの表示切り替え、「指を離すと、この一枚は流れていきます」
  という案内を表示

案内文（`#under-note`）は`min-height:3.9em`（[shor.html:563](../shor.html#L563)）を
持たせてあり、表示/非表示で本文の高さが変わらないようにしている。この文言は
`<br>`で強制的に2行になるため、以前`min-height`が2行分に足りておらず、
文言が出た瞬間にscr-view全体の位置がわずかにずれるバグがあった（修正済み）。

`t < 1`の間は`requestAnimationFrame`で自分自身を呼び続ける
（`pressing`が`false`になった時点で自然に止まる）。

## 押し始め: `pointerdown`

`zone.setPointerCapture(e.pointerId)`（[shor.html:1383](../shor.html#L1383)）
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
   （[shor.html:1403-1407](../shor.html#L1403-L1407)。UIのwash演出はこれを
   待たずに即座に始まる — 詳細は[distribution.md](distribution.md)の
   「peek → confirm」節）
3. ポラロイドに`washed`クラス付与と同時に、案内文（`#view-screen-note`）の
   文言を「あなたの一枚も、流してみませんか」に差し替えてから`fading`クラスを
   付けてフェードアウトする（写真が流れ去る演出に合わせた投稿への誘導）。
   `.screen-note`の`padding-top`は画面高600px〜950pxでclamp()により
   `8px`〜`16px`の範囲で可変（[shor.html:567-569](../shor.html#L567-L569)）。
   `margin-top:auto`は`.screen`が高さを持たない（コンテンツの高さぶんしか
   ない）ため実際には効かず、直前の要素（ポラロイド）に隣接する形で
   描画される。詳細は[screens.md](screens.md)の「レイアウトのレスポンシブ
   対応」節参照
4. 1500ms後、要素をリセットして次の画面へ:
   `viewOrigin === "done"` なら`renderHome()`、それ以外は`openPost()`
   （投稿完了画面経由で見た場合も、現像後は投稿完了画面には戻らずホームへ
   抜ける意図的な仕様。詳細は[screens.md](screens.md)のscr-view節参照）。
   同じタイミングで案内文を元の「※写真の保存はご遠慮ください」に戻し、
   次にこの画面を開いたときのために復元しておく

### 現像未完了のまま離した場合（`developed === false`）

`resetDevelop(false)`で見た目を巻き戻し、「現像するには指を置いたままに
してください」と表示（3000msで自動的に消える）。**画面は遷移せず、
同じ写真のまま**再度長押しに挑戦できる（枠もサーバ予約もまだ何も
消費されていないため、やり直しは何度でも自由 — [view-grants.md](view-grants.md)参照）。

## タッチ操作全般の制約

`shor.html`全体で長押しメニュー・選択・ドラッグ保存を無効化している。
CSS側（[shor.html:59-68](../shor.html#L59-L68)）で
`user-select`/`touch-callout`/`user-drag`等を`none`にし、その上でJS側
（[shor.html:1119-1120](../shor.html#L1119-L1120)、`contextmenu`/`selectstart`/
`dragstart`の`preventDefault`）が「最終防衛線」として二重に無効化している。
これは現像ゾーンの長押しがOS標準のコンテキストメニューやテキスト選択と
衝突しないようにするための、アプリ全体にかかる前提。
