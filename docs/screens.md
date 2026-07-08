# 画面遷移

`shor.html`には4つの`.screen`セクションがあり、`show(id)`
（[shor.html:582](../shor.html#L582)）が`.active`クラスを付け替えることで
1画面だけを表示する（CSSのフェードは[shor.html:94-102](../shor.html#L94-L102)）。
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

- 表示関数: `renderHome()`（[shor.html:619](../shor.html#L619)）
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

- 表示関数: `openView(origin)`（[shor.html:666](../shor.html#L666)）。
  `origin`は`"home"`か`"done"`で、現像後にどちらへ戻るかを覚えておくために使う
- `peek_drift`で候補が0件だった場合、または候補は返ってきたが
  `drift.image_url`の読み込みに失敗した場合（ストレージから画像が手動削除
  された直後など、`imageLoads()`で先読みチェックしている
  [shor.html:657-664](../shor.html#L657-L664) / [shor.html:685](../shor.html#L685)）:
  どちらも同じ扱いで「まだ写真が届いていません」とささやき表示後、
  1400ms後に`origin==="done"`なら`backToDone()`、それ以外は`renderHome()`
  （壊れた画像をそのまま表示することはない）
- 候補の取得に成功すると、写真がすぐには見えず前置き演出を挟む
  （[shor.html:700-707](../shor.html#L700-L707)）:
  1. 1250ms後、前置きメッセージ「あなたのもとへ 誰かのボトルメールが
     流れ着いたようです。」がフェードイン
  2. 3300ms後、そのメッセージがフェードアウトし始める
  3. 4200ms後、伏せられていたポラロイド（`view-polaroid`）が明ける
  - フェードイン/アウトの所要時間（見えるまで・消えるまでの長さ）は、
    前置きメッセージ・ホーム→scr-viewの画面遷移が共通の`--dur-fade`
    （1100ms、[shor.html:37](../shor.html#L37)）を使っているのに対し、
    ポラロイド（`view-polaroid`）だけは`--dur-fade-photo`
    （1600ms、[shor.html:38](../shor.html#L38)）という別変数を使っている。
    写真は他の要素より体感速度が速く感じられたため、意図的にポラロイドだけ
    長めにしてある（[shor.html:165-167](../shor.html#L165-L167)）。
    上記の1250/3300/4200msは、あくまで「いつフェードを開始するか」の
    タイミングであり、フェード自体の長さとは別
- 現像インタラクション完了（長押しをやり切って指を離す）後、washのアニメーション
  を経て:
  - `origin==="done"`（[shor.html:788](../shor.html#L788),
    [shor.html:789](../shor.html#L789)）→ `backToDone()`（→scr-done）
  - それ以外 → `openPost()`（→scr-post）
- 長押しを最後までやり切らずに離した場合はこの画面に留まり、同じ写真に
  再挑戦できる（`resetDevelop(false)`、[develop-interaction.md](develop-interaction.md)参照）

## scr-post（画面3: 投稿）

- 表示関数: `openPost()`（[shor.html:810](../shor.html#L810)）
- 呼ばれるタイミング: scr-homeの「写真を海に流す」、scr-viewでの現像完了後
  （閲覧起点がhomeの場合）、scr-doneの「もう一通海に流す」
  （`btn-post-again`）
- 送信（`btn-send`）成功後: ポラロイドと導入文をwashしてから
  `openDone()`を呼び、フォームをリセットする
- 「TOPへ戻る」（`post-to-top`）→ `renderHome()`（→scr-home）

## scr-done（画面4: 投稿完了）

- 表示関数: `openDone()`（[shor.html:949](../shor.html#L949)、投稿直後）
  / `backToDone()`（[shor.html:950](../shor.html#L950)、閲覧起点がdoneの
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
（`showModal()`/`hideModal()`, [shor.html:1001-1007](../shor.html#L1001-L1007)）。

- `result-modal`（前日の投稿結果） — `withResultGate()`が、保留中の結果が
  あるときにボタン操作をブロックして先に表示する。閉じると元々押した
  ボタンの遷移が走る（[view-grants.md](view-grants.md)参照）
- `notice-modal`（閲覧枠切れ等のお知らせ） — `canView()`が`false`のときに
  `btn-see`/`btn-give2see`から表示。texts は
  [view-grants.md](view-grants.md)の表を参照

どちらも背後の`.screen`は変化しない（画面遷移ではなく一時的な重ね表示）。
