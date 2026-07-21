# 画面遷移

`shor.html`には4つの`.screen`セクションがあり、`show(id)`
（[shor.html:922](../shor.html#L922)）が`.active`クラスを付け替えることで
1画面だけを表示する（CSSのフェードは[shor.html:111-119](../shor.html#L111-L119)）。
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

- 表示関数: `renderHome()`（[shor.html:959-988](../shor.html#L959-L988)）
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

- 表示関数: `openView(origin)`（[shor.html:1035](../shor.html#L1035)）。
  `origin`は`"home"`か`"done"`で、現像後にどちらへ戻るかを覚えておくために使う
- `peek_drift`で候補が0件だった場合、または候補は返ってきたが
  `drift.image_url`の読み込みに失敗した場合（ストレージから画像が手動削除
  された直後など、`imageLoads()`で先読みチェックしている
  [shor.html:1026-1033](../shor.html#L1026-L1033) / [shor.html:1057](../shor.html#L1057)）:
  どちらも同じ扱いで、まず`origin==="done"`なら`backToDone()`、それ以外は
  `renderHome()`で先に画面を戻してから、`notice-modal`
  （[shor.html:1063-1064](../shor.html#L1063-L1064)）で「まだ写真が届いていません。
  あなたが最初の一人になりませんか？」と知らせる（壊れた画像をそのまま
  表示することはない）。以前は画面下部固定の`whisper()`を使っていたが、
  `backToDone()`で投稿完了画面に戻った直後だと同じく画面下部にある
  `#pwa-note`（PWA案内）と文字が重なる事故があったため、先に画面遷移を
  済ませてからモーダルで知らせる方式に変更した
- 候補の取得に成功すると、写真がすぐには見えず前置き演出を挟む
  （[shor.html:1072-1080](../shor.html#L1072-L1080)）:
  1. 1250ms後、前置きメッセージ「あなたのもとへ 誰かのボトルメールが
     流れ着いたようです。」がフェードイン
  2. 3300ms後、そのメッセージがフェードアウトし始める
  3. 4500ms後（メッセージのフェードアウトが完全に終わってから）、
     「ひもで結ばれた巻紙がほどけてポラロイドが開く」演出を開始する
     （`.unroll-stage`に`play`クラスを追加）
- 巻紙が開く演出（`.unroll-stage`, [shor.html:206-269](../shor.html#L206-L269)）は、
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
    即座に切り替える（[shor.html:270-274](../shor.html#L270-L274)）
  - フェードイン/アウトの所要時間そのもの（前置きメッセージ・ホーム→scr-viewの
    画面遷移）は共通の`--dur-fade`（1100ms、[shor.html:52](../shor.html#L52)）を
    使っている。`--dur-fade-photo`（1600ms、[shor.html:53](../shor.html#L53)）は
    現在ポラロイドの登場には使われておらず、`washed`クラスによる退出（波に
    さらわれる）アニメーションにのみ使われている（[shor.html:192](../shor.html#L192)）
  - 上記の1250/3300/4500msは、あくまで「いつ演出を開始するか」のタイミング
- 現像インタラクション完了（長押しをやり切って指を離す）後、washのアニメーション
  を経て:
  - `origin==="done"`（[shor.html:1155](../shor.html#L1155)）→ `renderHome()`
    （→scr-home）。投稿完了画面経由で見た場合も、現像後は投稿完了画面には
    戻らずホームへ抜ける（意図的な仕様。「候補0件」で見られなかった場合の
    `backToDone()`分岐（[shor.html:1063](../shor.html#L1063)）とは扱いが違う点に注意）
  - それ以外 → `openPost()`（[shor.html:1156](../shor.html#L1156)、→scr-post）
- 長押しを最後までやり切らずに離した場合はこの画面に留まり、同じ写真に
  再挑戦できる（`resetDevelop(false)`、[develop-interaction.md](develop-interaction.md)参照）

## scr-post（画面3: 投稿）

- 表示関数: `openPost()`（[shor.html:1191-1200](../shor.html#L1191-L1200)）
- 呼ばれるタイミング: scr-homeの「写真を海に流す」、scr-viewでの現像完了後
  （閲覧起点がhomeの場合）、scr-doneの「もう一通海に流す」
  （`btn-post-again`）
- `openPost()`は`show("scr-post")`の直後に`new Image().src = "bottle.png"`
  で送り出し演出用のボトル画像を先読みする（同ファイル内）。ボトルは演出
  開始から約3.2秒後に初めて表示される（下記）ため、投稿完了直前ではなく
  投稿画面を開いた時点で先読みしておくことで、初回投稿時にボトルが欠けたり
  遅れて表示されたりしないようにしている。2回目以降はブラウザキャッシュが
  効くため、`openPost()`を呼ぶたびに実行しても無害
- 送信（`btn-send`）API成功後: `playSendoff()`
  （[shor.html:1312-1349](../shor.html#L1312-L1349)）を呼び、
  送り出し演出（下記）を再生してから`openDone()`を呼び、フォームを
  リセットする。API失敗時は演出を再生せず、エラー文言のみ表示する

### 投稿完了の送り出し演出（`playSendoff()`）

受け取り演出（scr-viewの`.unroll-stage`、[shor.html:206-274](../shor.html#L206-L274)）
と対になる、投稿完了時の演出。`.sendoff-stage`/`.sendoff-overlay`への
`play`クラス付与だけで全ての間合いをCSSアニメーションに任せており、
JS側は再生開始と合計`SENDOFF_TOTAL_MS`（6.8秒）後の後始末しか行わない
（`openDone()`呼び出し、`post-lead`・フォームのリセット）。演出中は
`.sendoff-overlay.play`が画面全体を覆う`position:fixed`要素として
`pointer-events:auto`になるため、操作はブロックされる
（[shor.html:276-392](../shor.html#L276-L392)）。

後始末は2段階に分かれている（`playSendoff()`,
[shor.html:1312-1349](../shor.html#L1312-L1349)）。`SENDOFF_TOTAL_MS`後、
`openDone()`と`overlay`の後始末は即座に行うが、`.sendoff-stage`の
`play`クラス解除だけは、その内側の1250ms後のsetTimeout
（`resetPostForm()`と同じタイミング）まで遅らせている。`.play`を外すと
`.sendoff-clip`の`clip-path`が全開（`inset(0 0 0 0)`）の初期状態へ即座に
戻るため、`openDone()`と同時に外すと、`scr-post`から`scr-done`への
画面遷移フェード（`--dur-fade`）の最中に投稿写真とカードが一瞬再表示
されてしまう。`scr-post`が完全に不可視になり切った後まで巻き取り状態
（`clip-path`が閉じ切ったまま）を維持することで、これを防いでいる。

一方`done-body`の`pending`クラス（`.done-body.pending{opacity:0}`）は
`openDone()`と**同時に**外している。以前はこれも上記の1250ms後の
setTimeoutにまとめていたが、そうすると画面自体の`--dur-fade`（1100ms）
のフェードが終わった後に`done-body`側の1100msフェードがさらに続けて
走ってしまい、ボトルが消えてから投稿完了画面の文言が読めるまでが
不必要に長く（2秒以上）感じられていた。`stage`の`.play`解除とは事情が
異なり（`done-body`のフェードは`scr-post`が隠れ切るのを待つ理由が無い）、
`openDone()`直後に外すことで画面自体のフェードと同時にコンテンツが
現れるようにしてある。

1. **ポラロイドが上へ巻かれる**（0〜2.2s）: 巻かれるのはアニメ専用の複製
   ではなく、画面に表示されている`#post-polaroid`（投稿カードそのもの）。
   これを包む`.sendoff-shadow`（drop-shadow） > `.sendoff-clip`（`clip-path`、
   [shor.html:294-302](../shor.html#L294-L302)）の`clip-path`が
   `inset(0 0 4.5px 0)`→`inset(0 0 calc(100% - 13px) 0)`へ変化する
   （`sendoffRollUp`, [shor.html:349-352](../shor.html#L349-L352)）。
   終点を`100%`（完全に消える）ではなく`calc(100% - 13px)`に、始点を
   `0`ではなく`4.5px`にしているのは、**clip境界を筒の中心に一致させる**
   ため。筒（`sendoffTubeUp`）は`top`基準で`top:calc(100% - 9px);height:9px`
   →`top:0;height:26px`と動くため、筒の中心（`top + height/2`）は
   0%地点で`H-4.5`、100%地点で`13`（`H`はカード高さ）。clip境界を単純に
   `0→100%`（高さゼロの線）で動かすと、筒の高さぶん境界が置き去りになり、
   巻き終わり間際に筒の上にカードの帯が薄く残って見える不具合があった。
   境界=筒の中心を0%/100%の両端で満たすよう、clipの終点残し幅を筒の
   最終高さの半分（13px）、始点の残し幅を筒の初期高さの半分（4.5px）に
   することで、clipとtubeが同じduration・イージングで動く限り常に
   一致するようにしている。

   ただし`sendoffRollUp`終了時点（2.2s）ではカード上部13px分がまだ
   意図的に残っており、その間は筒（`height:26px`、[0,26]の範囲）が
   その残りを覆い隠している。筒自体は2.7〜3.2sの`sendoffTubeFade`で
   フェードアウトするため、何もしなければ筒が消えた瞬間に残り13pxの
   帯だけが宙に浮いて見えてしまう。これを防ぐため、`.sendoff-clip`には
   `sendoffClipFinish`（[shor.html:349-352](../shor.html#L349-L352)）を
   `sendoffRollUp`と並べて重ね、`sendoffTubeFade`と全く同じ`.5s ease 2.7s`
   で残り13pxを`inset(0 0 100% 0)`（完全に閉じ切る）まで動かしている。
   筒が透明になり切るタイミングと、カードが完全に見えなくなるタイミングが
   一致するため、帯が浮いて見えることはない（`round`修飾は付けていない。
   角丸はここではなく`.sendoff-clip`の`overflow:hidden`+`border-radius:2px`
   （静的）だけが担う。`round`付きclip-pathをアニメーションさせると
   ブラウザによっては角丸矩形の再計算が毎フレーム正しく行われず、筒より
   下にカードが薄く残って見えることがあるため、アニメ対象のclip-pathから
   はroundを外し、角丸をoverflow:hidden側に一本化した）。`#post-polaroid`
   自身の`box-shadow`（`.polaroid`, [shor.html:178-179](../shor.html#L178-L179)）も
   この`overflow:hidden`で同じ境界に収まる。

   `.sendoff-shadow`には見た目に影響しない`transform:translateZ(0)`
   （[shor.html:286-293](../shor.html#L286-L293)）も付けてある。受け取り
   演出側の`.polaroid-shadow`には`rotate(1.5deg)`があり、それが独立した
   合成レイヤーを作る副作用で`filter:drop-shadow`が子の`clip-path`アニメ
   ーションに毎フレーム正しく追従しているが、送り出し側の`.sendoff-shadow`
   にはtransformが無く、この差のせいで影がclip前の古い形状のまま描画され
   続け、筒より下にカードの影が薄いゴーストとして残って見えることがあった。
   `.sendoff-clip`側にも`will-change:clip-path`を付け、同様に正しいレイヤー
   化を促している。加えて`.sendoff-stage.play
   .polaroid{backdrop-filter:none;-webkit-backdrop-filter:none}`
   （[shor.html:312-315](../shor.html#L312-L315)）で演出中は
   `backdrop-filter`を明示的に無効化している。WebKitは`backdrop-filter`
   を持つ要素の背景ぼかし層を祖先の`clip-path`で正しく切り取れないことが
   あり、カード本体が消えても層だけ筒の下に残って見えることがあるための
   対策。`.sendoff-roll`（筒）は同じ`.sendoff-stage`を基準に`left`/`right`
   をカードと揃えて配置しており、`clip-path`の進行（`sendoffRollUp`）と
   筒の上昇（`sendoffTubeUp`）はどちらも同じ2.2s・
   `cubic-bezier(.4,.1,.3,1)`で同期している。
   筒（`.sendoff-tube`のグラデーションは受け取り演出の`.roll-tube`と
   同じ値を使っている）は下端（`height:9px`）から上端（`height:26px`）へ
   移動する。ひもを結ぶ演出は無い（`.string`は受け取り演出専用のまま）
2. **0.5秒静止後、筒がフェードアウト**（2.2〜2.7s静止、2.7〜3.2sでopacity 1→0）
3. **ボトル画像がフェードイン**（3.2〜4.0s。`rotate(-3deg)`固定、
   `scale .97→1`）: `.sendoff-bottle`内は自作SVGではなく背景透過の実写画像
   `bottle.png`（`<img src="bottle.png" alt="" width="190">`,
   [shor.html:659-661](../shor.html#L659-L661)）。`.sendoff-bottle`自体の
   `opacity`/`transform`アニメーションと`filter:drop-shadow`は変更しておらず、
   drop-shadowは透過画像の輪郭に沿って効く
4. **ボトルが漂いながら退場**（4.0〜6.4s）: `translate(58px,-50px)`の
   右斜め上へ、緩い弧を描くように移動する（40%地点で`translate(22px,-26px)`
   を経由、`rotate`は指定せず0%の`-3deg`から100%の`-8deg`へ直接補間する
   ことで、一方向に傾きが増え続ける自然な動きになる。以前は45%地点で
   `rotate(-5deg)`へ振ってから`-3deg`へ戻す往復があり、流れていく途中で
   不自然に揺れて見えていたため撤去した）。`scale 1→.88`、opacity 1→0。
   ボトルが消え切る6.4sの少し後、`SENDOFF_TOTAL_MS`（6.8s）で
   `playSendoff()`内のsetTimeoutが発火し既存の完了遷移へ

以前は演出の最後にオーバーレイ内で「あなたの一枚が、誰かの岸へ向かって
います」というメッセージを別途フェードインさせ、数秒静止してから遷移
していたが、この文言専用のステップ（`#sendoff-message`）は廃止した。
現在は同じ文言を投稿完了画面（scr-done）の`.done-main`先頭の常設テキスト
として表示している（`<p class="passage">`、[shor.html:670](../shor.html#L670)）。
これにより演出の総時間も10秒から6.8秒に短縮された。

`prefers-reduced-motion: reduce`環境では、`.sendoff-stage.play`を
`display:none`にしてポラロイドの巻き上げ演出をスキップする。メッセージ
文言はscr-done側の常設テキストとして表示されるため、演出用のフォール
バック表示は不要になった。ボトルは元々装飾用で、CSSの初期値
`opacity:0`のまま、グローバルなアニメーション無効化ルールに従って
非表示になる。**スコープは`.play`中に限定**しており、投稿前の
写真選択中の表示（`.sendoff-stage`は常設）まで消えないよう注意している。

- 「TOPへ戻る」（`post-to-top`）→ `renderHome()`（→scr-home）

## scr-done（画面4: 投稿完了）

- 表示関数: `openDone()`（[shor.html:1411](../shor.html#L1411)、投稿直後）
  / `backToDone()`（[shor.html:1412](../shor.html#L1412)、閲覧起点がdoneで
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
    （[shor.html:151-162](../shor.html#L151-L162)、JS側は
    [shor.html:1433-1462](../shor.html#L1433-L1462)）

## モーダル（画面遷移ではなく重ね表示）

`.screen`とは別に、現在の画面の上に重ねて出すモーダルが3つある
（`showModal()`/`hideModal()`, [shor.html:1472-1478](../shor.html#L1472-L1478)）。

- `result-modal`（投稿結果） — `withResultGate()`
  （[shor.html:993-1000](../shor.html#L993-L1000)）が、`pendingResults`
  （前日以前に投稿してまだ結果を見せていない投稿の配列、古い順）に
  1件以上あるときボタン操作をブロックして先に表示する。中身は
  `showNextResult()`（[shor.html:1002-1016](../shor.html#L1002-L1016)）が
  1件popして描画する:
  - `#result-sec`に秒数（`view_history.viewed_seconds`の合計、
    `getResultForPost()`で投稿単位に集計）
  - サムネイルがあれば`#result-thumb`に表示。無ければ非表示のまま
    （この機能を入れる前からの保留分は日付単位の合算で、サムネイルを
    持たないため秒数のみになる。[data-model.md](data-model.md)の
    「投稿結果表示用のローカルストレージ」参照）

  モーダルを閉じる（`closeResultModal()`, [shor.html:1480-1489](../shor.html#L1480-L1489)）
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
