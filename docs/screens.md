# 画面遷移

`shor.html`には4つの`.screen`セクションがあり、`show(id)`
（[shor.html:566](../shor.html#L566)）が`.active`クラスを付け替えることで
1画面だけを表示する（CSSのフェードは[shor.html:85-93](../shor.html#L85-L93)）。
現像インタラクション（長押し）そのものの詳細は
[develop-interaction.md](develop-interaction.md)を参照。

```
scr-home ──「誰かの感性に触れる」──▶ scr-view ──現像完了──▶ scr-post ──送信──▶ scr-done
   ▲                                    │                                    │
   │◀────────────「TOPへ戻る」───────────┘                                    │
   │◀─────────────────────「TOPへ戻る」────────────────────────────────────┘
   │
   └─◀── scr-done「誰かの感性に触れる」──▶ scr-view ──現像完了──▶ scr-done（戻る）
```

## scr-home（画面1: ダッシュボード）

- 表示関数: `renderHome()`（[shor.html:603](../shor.html#L603)）
- 呼ばれるタイミング: 起動時、および各画面の「TOPへ戻る」
  （`post-to-top`, `done-to-top`）
- 前日の投稿結果が未確認なら`pendingResult`にセットするだけで、この時点では
  モーダルを出さない（[view-grants.md](view-grants.md)の`withResultGate`参照）
- ボタン:
  - `btn-see`「誰かの感性に触れる」→ `withResultGate`でラップ→
    `canView()`が`false`なら`notice-modal`を表示、`true`なら
    `openView("home")`（→scr-view）
  - `home-to-post`「写真を海に流す」→ `withResultGate`でラップ→
    `openPost()`（→scr-post）

## scr-view（画面2: 閲覧/現像）

- 表示関数: `openView(origin)`（[shor.html:641](../shor.html#L641)）。
  `origin`は`"home"`か`"done"`で、現像後にどちらへ戻るかを覚えておくために使う
- `peek_drift`で候補が0件だった場合: 「まだ写真が届いていません」と
  ささやき表示後、1400ms後に`origin==="done"`なら`backToDone()`、
  それ以外は`renderHome()`
- 現像インタラクション完了（長押しをやり切って指を離す）後、washのアニメーション
  を経て:
  - `origin==="done"`（[shor.html:663](../shor.html#L663),
    [shor.html:761](../shor.html#L761)）→ `backToDone()`（→scr-done）
  - それ以外 → `openPost()`（→scr-post）
- 長押しを最後までやり切らずに離した場合はこの画面に留まり、同じ写真に
  再挑戦できる（`resetDevelop(false)`、[develop-interaction.md](develop-interaction.md)参照）

## scr-post（画面3: 投稿）

- 表示関数: `openPost()`（[shor.html:783](../shor.html#L783)）
- 呼ばれるタイミング: scr-homeの「写真を海に流す」、scr-viewでの現像完了後
  （閲覧起点がhomeの場合）、scr-doneの「もう一通海に流す」
  （`btn-post-again`）
- 送信（`btn-send`）成功後: ポラロイドと導入文をwashしてから
  `openDone()`を呼び、フォームをリセットする
- 「TOPへ戻る」（`post-to-top`）→ `renderHome()`（→scr-home）

## scr-done（画面4: 投稿完了）

- 表示関数: `openDone()`（[shor.html:922](../shor.html#L922)、投稿直後）
  / `backToDone()`（[shor.html:923](../shor.html#L923)、閲覧起点がdoneの
  ときに現像完了後戻ってくる場合。`done-body`のpendingクラスを一旦外して
  再アニメーションできる状態に戻す）
- ボタン:
  - `btn-give2see`「誰かの感性に触れる」→ `canView()`が`false`なら
    `notice-modal`、`true`なら`openView("done")`（→scr-view、
    ここでの`origin`は`"done"`なので現像完了後はscr-doneに戻ってくる）
  - `btn-post-again`「もう一通海に流す」→ `openPost()`（→scr-post）
  - `done-to-top`「TOPへ戻る」→ `renderHome()`（→scr-home）
  - `btn-pwa`「ホーム画面に追加する」→ PWAインストールプロンプト
    （`beforeinstallprompt`が発火していれば）、無ければ手動追加を促す
    ささやき表示

## モーダル（画面遷移ではなく重ね表示）

`.screen`とは別に、現在の画面の上に重ねて出す2つのモーダルがある
（`showModal()`/`hideModal()`, [shor.html:955-964](../shor.html#L955-L964)）。

- `result-modal`（前日の投稿結果） — `withResultGate()`が、保留中の結果が
  あるときにボタン操作をブロックして先に表示する。閉じると元々押した
  ボタンの遷移が走る（[view-grants.md](view-grants.md)参照）
- `notice-modal`（閲覧枠切れ等のお知らせ） — `canView()`が`false`のときに
  `btn-see`/`btn-give2see`から表示。texts は
  [view-grants.md](view-grants.md)の表を参照

どちらも背後の`.screen`は変化しない（画面遷移ではなく一時的な重ね表示）。
