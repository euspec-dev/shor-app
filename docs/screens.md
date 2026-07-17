# 画面遷移

`shor.html`には4つの`.screen`セクションがあり、`show(id)`
（[shor.html:774](../shor.html#L774)）が`.active`クラスを付け替えることで
1画面だけを表示する（CSSのフェードは[shor.html:98-106](../shor.html#L98-L106)）。
現像インタラクション（長押し）そのものの詳細は
[develop-interaction.md](develop-interaction.md)を参照。

```
scr-home ──「誰かの感性に触れる」──▶ scr-view ──現像完了──▶ scr-post ──送信──▶ scr-done
   ▲                                    │                                    │
   │◀────────────「TOPへ戻る」───────────┘                                    │
   │◀─────────────────────「TOPへ戻る」────────────────────────────────────┘
   │
   └─◀── scr-done「誰かの感性に触れる」──▶ scr-view ──現像完了──▶ scr-home（戻らない）
```

## scr-home（画面1: ダッシュボード）

- 表示関数: `renderHome()`（[shor.html:811-840](../shor.html#L811-L840)）
- 呼ばれるタイミング: 起動時、および各画面の「TOPへ戻る」
  （`post-to-top`, `done-to-top`）
- 前日以前の投稿で未確認の結果があれば`pendingResults`（配列）に積むだけで、
  この時点ではモーダルを出さない。複数件あってもこの時点では全部貯める
  だけ（下記「結果モーダル」節参照）
- ボタン:
  - `btn-see`「誰かの感性に触れる」→ `withResultGate`でラップ→
    `canView()`が`false`なら`notice-modal`を表示、`true`なら
    `openView("home")`（→scr-view）
  - `home-to-post`「写真を海に流す」→ `withResultGate`でラップ→
    `openPost()`（→scr-post）

## scr-view（画面2: 閲覧/現像）

- 表示関数: `openView(origin)`（[shor.html:887](../shor.html#L887)）。
  `origin`は`"home"`か`"done"`で、現像後にどちらへ戻るかを覚えておくために使う
- `peek_drift`で候補が0件だった場合、または候補は返ってきたが
  `drift.image_url`の読み込みに失敗した場合（ストレージから画像が手動削除
  された直後など、`imageLoads()`で先読みチェックしている
  [shor.html:878-885](../shor.html#L878-L885) / [shor.html:909](../shor.html#L909)）:
  どちらも同じ扱いで、まず`origin==="done"`なら`backToDone()`、それ以外は
  `renderHome()`で先に画面を戻してから、`notice-modal`
  （[shor.html:915-916](../shor.html#L915-L916)）で「まだ写真が届いていません。
  あなたが最初の一人になりませんか？」と知らせる（壊れた画像をそのまま
  表示することはない）。以前は画面下部固定の`whisper()`を使っていたが、
  `backToDone()`で投稿完了画面に戻った直後だと同じく画面下部にある
  `#pwa-note`（PWA案内）と文字が重なる事故があったため、先に画面遷移を
  済ませてからモーダルで知らせる方式に変更した
- 候補の取得に成功すると、写真がすぐには見えず前置き演出を挟む
  （[shor.html:924-932](../shor.html#L924-L932)）:
  1. 1250ms後、前置きメッセージ「あなたのもとへ 誰かのボトルメールが
     流れ着いたようです。」がフェードイン
  2. 3300ms後、そのメッセージがフェードアウトし始める
  3. 4500ms後（メッセージのフェードアウトが完全に終わってから）、
     「ひもで結ばれた巻紙がほどけてポラロイドが開く」演出を開始する
     （`.unroll-stage`に`play`クラスを追加）
- 巻紙が開く演出（`.unroll-stage`, [shor.html:188-256](../shor.html#L188-L256)）は、
  参考実装`shor_polaroid_unroll_v2.html`を土台に、実際のポラロイド本体
  （キャプション・ぼかし写真・現像ゾーンを含む可変高さの`#view-polaroid`）を
  `.polaroid-shadow`（影担当）＞`.polaroid-clip`（clip-path担当）で
  二重に包む形で統合してある。固定ピクセル値ではなく`%`/`calc()`で
  本体の実際の高さに追従する:
  1. ひもが揺れて落ちる（`strFall`, 0.95s）
  2. 巻紙が中央から上端へ移動する（`rollGo`前半、25%まで）
  3. 巻紙が上端から下端へ転がりながら消えると同時に、`.polaroid-clip`の
     `clip-path`が上から下へ開いていき、中の`#view-polaroid`が現れる
     （`sheetOpen`, 1.95s）
  4. 開き切った直後、紙が落ち着くような小さな沈み込み（`sheetSettle`）
  - ポラロイドの傾き（`rotate(1.5deg)`）は`#view-polaroid`自身ではなく
    `.polaroid-shadow`（`.polaroid-clip`と同じ外側）に付けてある。中身だけを
    回転させると`clip-path`の矩形が追従せず、開いていく途中で台形にゆがんで
    見えるため。巻紙（`.roll-wrap`）にも同じ`rotate(1.5deg)`を付けて、
    開く前後で傾きが一貫するようにしている
  - ぼかし（`filter:blur`、[develop-interaction.md](develop-interaction.md)参照）は
    写真の`.pic`要素側、`clip-path`は外側の`.polaroid-clip`側と別々の要素に
    分けているため、演出中に鮮明な写真が一瞬見えることはない
  - `prefers-reduced-motion: reduce`環境では、演出させずに開き切った状態へ
    即座に切り替える（[shor.html:252-256](../shor.html#L252-L256)）
  - フェードイン/アウトの所要時間そのもの（前置きメッセージ・ホーム→scr-viewの
    画面遷移）は共通の`--dur-fade`（1100ms、[shor.html:39](../shor.html#L39)）を
    使っている。`--dur-fade-photo`（1600ms、[shor.html:40](../shor.html#L40)）は
    現在ポラロイドの登場には使われておらず、`washed`クラスによる退出（波に
    さらわれる）アニメーションにのみ使われている（[shor.html:174](../shor.html#L174)）
  - 上記の1250/3300/4500msは、あくまで「いつ演出を開始するか」のタイミング
- 現像インタラクション完了（長押しをやり切って指を離す）後、washのアニメーション
  を経て:
  - `origin==="done"`（[shor.html:1007](../shor.html#L1007)）→ `renderHome()`
    （→scr-home）。投稿完了画面経由で見た場合も、現像後は投稿完了画面には
    戻らずホームへ抜ける（意図的な仕様。「候補0件」で見られなかった場合の
    `backToDone()`分岐（[shor.html:915](../shor.html#L915)）とは扱いが違う点に注意）
  - それ以外 → `openPost()`（[shor.html:1008](../shor.html#L1008)、→scr-post）
- 長押しを最後までやり切らずに離した場合はこの画面に留まり、同じ写真に
  再挑戦できる（`resetDevelop(false)`、[develop-interaction.md](develop-interaction.md)参照）

## scr-post（画面3: 投稿）

- 表示関数: `openPost()`（[shor.html:1043](../shor.html#L1043)）
- 呼ばれるタイミング: scr-homeの「写真を海に流す」、scr-viewでの現像完了後
  （閲覧起点がhomeの場合）、scr-doneの「もう一通海に流す」
  （`btn-post-again`）
- 送信（`btn-send`）成功後: ポラロイドと導入文をwashしてから
  `openDone()`を呼び、フォームをリセットする
- 「TOPへ戻る」（`post-to-top`）→ `renderHome()`（→scr-home）

## scr-done（画面4: 投稿完了）

- 表示関数: `openDone()`（[shor.html:1229](../shor.html#L1229)、投稿直後）
  / `backToDone()`（[shor.html:1230](../shor.html#L1230)、閲覧起点がdoneで
  かつ候補0件だったときのみ使用。`done-body`のpendingクラスを一旦外して
  再アニメーションできる状態に戻す。現像を最後までやり切った場合は
  `renderHome()`でscr-homeに抜けるため、この関数は呼ばれない）
- ボタン:
  - `btn-give2see`「誰かの感性に触れる」→ `canView()`が`false`なら
    `notice-modal`、`true`なら`openView("done")`（→scr-view、
    ここでの`origin`は`"done"`。現像を最後までやり切った場合はscr-doneには
    戻らずscr-homeへ抜ける。候補0件で見られなかった場合のみscr-doneに戻る）
  - `btn-post-again`「もう一通海に流す」→ `openPost()`（→scr-post）
  - `done-to-top`「TOPへ戻る」→ `renderHome()`（→scr-home）
  - `btn-pwa`「ホーム画面に追加する」→ PWAインストールプロンプト
    （`beforeinstallprompt`が発火していれば）、無ければ操作手順を
    ボタンの下の`#pwa-help`（ボタン上の`#pwa-note`とは別要素）に一時表示する。
    `whisper()`は固定位置でscr-doneのようなコンテンツの多い画面だと
    ボタンと重なるため使っていない。`#pwa-help`は`position:absolute`で
    通常のレイアウトの高さ計算に参加しないようにしてあり、押下前後で
    `#pwa-note`やボタンの位置が動かないようにしている
    （[shor.html:141-149](../shor.html#L141-L149)、JS側は
    [shor.html:1264-1285](../shor.html#L1264-L1285)）

## モーダル（画面遷移ではなく重ね表示）

`.screen`とは別に、現在の画面の上に重ねて出すモーダルが3つある
（`showModal()`/`hideModal()`, [shor.html:1290-1296](../shor.html#L1290-L1296)）。

- `result-modal`（投稿結果） — `withResultGate()`
  （[shor.html:845-852](../shor.html#L845-L852)）が、`pendingResults`
  （前日以前に投稿してまだ結果を見せていない投稿の配列、古い順）に
  1件以上あるときボタン操作をブロックして先に表示する。中身は
  `showNextResult()`（[shor.html:854-868](../shor.html#L854-L868)）が
  1件popして描画する:
  - `#result-sec`に秒数（`view_history.viewed_seconds`の合計、
    `getResultForPost()`で投稿単位に集計）
  - サムネイルがあれば`#result-thumb`に表示。無ければ非表示のまま
    （この機能を入れる前からの保留分は日付単位の合算で、サムネイルを
    持たないため秒数のみになる。[data-model.md](data-model.md)の
    「投稿結果表示用のローカルストレージ」参照）

  モーダルを閉じる（`closeResultModal()`, [shor.html:1298-1307](../shor.html#L1298-L1307)）
  たびに`pendingResults`が残っていれば次の1件を表示し、無くなって
  初めて元々押したボタンの遷移が走る。一覧・履歴のようなUIは無く、
  常に「今見せる1件」だけをモーダルで順に見せる設計
- `notice-modal`（閲覧枠切れ等のお知らせ） — `canView()`が`false`のときに
  `btn-see`/`btn-give2see`から表示。texts は
  [view-grants.md](view-grants.md)の表を参照
- `pick-choice-modal`（投稿写真の追加元選択、Androidのみ） — scr-postの
  `btn-pick`「＋ 写真を選ぶ」を押すと表示され、「写真を撮る」/
  「ギャラリーから選ぶ」でカメラ用/ギャラリー用の2つの
  `<input type=file>`のどちらを`.click()`するかを振り分ける。iOSでは
  Safari標準のアクションシートと選択が二重になるため、このモーダルは
  出さずファイル選択inputを直接開く（[data-model.md](data-model.md)の
  「投稿画像のバリデーション」参照）
  詳細は[data-model.md](data-model.md)の投稿バリデーションの節、
  実装は`shor.html`内`handlePickedFile(file, fromCamera)`周辺を参照

どちらも背後の`.screen`は変化しない（画面遷移ではなく一時的な重ね表示）。
