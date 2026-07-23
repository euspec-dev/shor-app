# 画面遷移

`shor.html`には4つの`.screen`セクションがあり、`show(id)`
（[shor.html:983](../shor.html#L983)）が`.active`クラスを付け替えることで
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

- 表示関数: `renderHome()`（[shor.html:1020-1049](../shor.html#L1020-L1049)）
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

- 表示関数: `openView(origin)`（[shor.html:1096](../shor.html#L1096)）。
  `origin`は`"home"`か`"done"`で、現像後にどちらへ戻るかを覚えておくために使う
- `peek_drift`で候補が0件だった場合、または候補は返ってきたが
  `drift.image_url`の読み込みに失敗した場合（ストレージから画像が手動削除
  された直後など、`imageLoads()`で先読みチェックしている
  [shor.html:1087-1094](../shor.html#L1087-L1094) / [shor.html:1118](../shor.html#L1118)）:
  どちらも同じ扱いで、まず`origin==="done"`なら`backToDone()`、それ以外は
  `renderHome()`で先に画面を戻してから、`notice-modal`
  （[shor.html:1124-1125](../shor.html#L1124-L1125)）で「まだ写真が届いていません。
  あなたが最初の一人になりませんか？」と知らせる（壊れた画像をそのまま
  表示することはない）。以前は画面下部固定の`whisper()`を使っていたが、
  `backToDone()`で投稿完了画面に戻った直後だと同じく画面下部にある
  `#pwa-note`（PWA案内）と文字が重なる事故があったため、先に画面遷移を
  済ませてからモーダルで知らせる方式に変更した
- 候補の取得に成功すると、写真がすぐには見えず前置き演出を挟む
  （[shor.html:1133-1145](../shor.html#L1133-L1145)）:
  1. 1250ms後、前置きメッセージ「あなたのもとへ 誰かのボトルメールが
     流れ着いたようです。」がフェードイン
  2. 3300ms後、そのメッセージがフェードアウトし始める
  3. 4500ms後（メッセージのフェードアウトが完全に終わってから）、
     「ひもで結ばれた巻紙がほどけてポラロイドが開く」演出を開始する
     （`.unroll-stage`に`play`クラスを追加）
- 巻紙が開く演出（`.unroll-stage`, [shor.html:206-318](../shor.html#L206-L318)）は、
  参考実装`shor_polaroid_unroll_v2.html`を土台に、実際のポラロイド本体
  （キャプション・ぼかし写真・現像ゾーンを含む可変高さの`#view-polaroid`）を
  `.polaroid-shadow`（影担当）＞`.polaroid-clip`（clip-path担当）で
  二重に包む形で統合してある。固定ピクセル値ではなく`%`/`calc()`で
  本体の実際の高さに追従する。対になる送り出し演出（`.sendoff-stage`、下記）
  の逆再生にあたり、以下の技法はsendoff側で先に確立したものをミラーしてある:
  1. ひもが揺れて落ちる（`strFall`, 0.95s）
  2. 巻紙が中央から上端へ移動する（`rollGo`前半、25%まで、専用のイージング）
  3. 巻紙が上端から下端の細い帯へ転がると同時に、`.polaroid-clip`の
     `clip-path`が上から下へ開いていき、中の`#view-polaroid`が現れる
     （`rollGo`後半とsheetOpen、どちらも同じ1.65s遅延・1.95sの長さ・同じ
     イージング`cubic-bezier(.4,.1,.3,1)`で動く）
  4. 巻紙が完全に消えるのと同時に、`.polaroid-clip`が最後に残ったわずかな
     隙間を閉じ切る（`rollFade`＋`sheetCloseFinish`、どちらも同じ.3s）
  5. 開き切った直後、紙が落ち着くような小さな沈み込み（`sheetSettle`）
  - **clipの境界は「筒の中心」に合わせてある**（筒の上端ではない）。筒は
    `top`基準で動くため、境界を単純に0%⇔100%で動かすと筒の高さぶん境界が
    置き去りになる。筒の中心=`top + height/2`なので、`rollGo`後半の開始地点
    （`top:0/height:26px`）の中心は13px、終了地点（`top:calc(100% - 9px)/
    height:9px`）の中心は`calc(100% - 4.5px)`となり、`sheetOpen`は
    `inset(0 0 calc(100% - 13px) 0)`→`inset(0 0 4.5px 0)`とその補正込みの
    値で動く（[shor.html:297-300](../shor.html#L297-L300)）。以前はこの補正が
    無く、単純に`100%`⇔`0`だったため、常に筒の中心と開口端が最大13pxずれて
    見える不具合があった
  - `rollGo`のopacityは以前は`top`/`height`と同じキーフレーム内（86%地点）
    に同居していたが、それだけのために86%でキーフレームが増え、25%区間の
    イージング指定が86%以降は既定の`ease`に戻ってしまい、後半で筒とカードの
    動きが分離するバグがあった。opacityは`rollFade`という別animationに
    分離し、`rollGo`の25%→100%区間は単一のイージングのまま`sheetOpen`と
    完全に同期させている
  - 演出中（`.rolling`クラスが付いている間、[shor.html:234](../shor.html#L234)、
    JS側は[shor.html:1138-1145](../shor.html#L1138-L1145)）は`.frost`の
    `backdrop-filter`を無効化する。WebKitは`backdrop-filter`を持つ要素の
    背景ぼかし層を祖先の`clip-path`で切り取れないことがあり、無効化しないと
    巻紙が完全に閉じていてもぼかしガラス層だけが筒の外にはみ出て見えることが
    ある。ただし`#view-polaroid`は演出後も現像インタラクションで
    `.frost`のぼかしを使い続けるため、`.play`とは別に`.rolling`という
    演出専用クラスを設け、巻紙が開き切る頃（演出開始から4.1s後）にJSで
    外して元に戻している
  - `.polaroid-clip`は`clip-path`に`round`を付けず、`overflow:hidden`＋
    静的な`border-radius:2px`だけで角丸を担う（[shor.html:220-227]
    (../shor.html#L220-L227)）。`round`付きの`clip-path`をアニメーション
    させると、ブラウザによっては角丸矩形の再計算が毎フレーム正しく行われず、
    境界付近にカードが薄く残ることがあるため
  - ポラロイドの傾き（`rotate(1.5deg)`）は`#view-polaroid`自身ではなく
    `.polaroid-shadow`（`.polaroid-clip`と同じ外側）に付けてある。中身だけを
    回転させると`clip-path`の矩形が追従せず、開いていく途中で台形にゆがんで
    見えるため。巻紙（`.roll-wrap`）にも同じ`rotate(1.5deg)`を付けて、
    開く前後で傾きが一貫するようにしている。このrotateは同時に、
    `backdrop-filter`が`clip-path`の毎フレームの変化に正しく追従するための
    独立した合成レイヤーも作っている（送り出し演出側の`.sendoff-shadow`は
    rotateが無いため、代わりに`transform:translateZ(0)`で同じ効果を得ている）
  - ぼかし（`filter:blur`、[develop-interaction.md](develop-interaction.md)参照）は
    写真の`.pic`要素側、`clip-path`は外側の`.polaroid-clip`側と別々の要素に
    分けているため、演出中に鮮明な写真が一瞬見えることはない
  - `prefers-reduced-motion: reduce`環境では、演出させずに開き切った状態へ
    即座に切り替える（[shor.html:314-318](../shor.html#L314-L318)）
  - フェードイン/アウトの所要時間そのもの（前置きメッセージ・ホーム→scr-viewの
    画面遷移）は共通の`--dur-fade`（1100ms、[shor.html:52](../shor.html#L52)）を
    使っている。`--dur-fade-photo`（1600ms、[shor.html:53](../shor.html#L53)）は
    現在ポラロイドの登場には使われておらず、`washed`クラスによる退出（波に
    さらわれる）アニメーションにのみ使われている（[shor.html:192](../shor.html#L192)）
  - 上記の1250/3300/4500msは、あくまで「いつ演出を開始するか」のタイミング
- 現像インタラクション完了（長押しをやり切って指を離す）後、washのアニメーション
  を経て:
  - `origin==="done"`（[shor.html:1220](../shor.html#L1220)）→ `renderHome()`
    （→scr-home）。投稿完了画面経由で見た場合も、現像後は投稿完了画面には
    戻らずホームへ抜ける（意図的な仕様。「候補0件」で見られなかった場合の
    `backToDone()`分岐（[shor.html:1124](../shor.html#L1124)）とは扱いが違う点に注意）
  - それ以外 → `openPost()`（[shor.html:1221](../shor.html#L1221)、→scr-post）
- 長押しを最後までやり切らずに離した場合はこの画面に留まり、同じ写真に
  再挑戦できる（`resetDevelop(false)`、[develop-interaction.md](develop-interaction.md)参照）

## scr-post（画面3: 投稿）

- 表示関数: `openPost()`（[shor.html:1438-1447](../shor.html#L1438-L1447)）
- 呼ばれるタイミング: scr-homeの「写真を海に流す」、scr-viewでの現像完了後
  （閲覧起点がhomeの場合）、scr-doneの「もう一通海に流す」
  （`btn-post-again`）
- `openPost()`は`show("scr-post")`の直後に`new Image().src = "bottle.png"`
  で送り出し演出用のボトル画像を先読みする（同ファイル内）。ボトルは演出
  開始から約3.2秒後に初めて表示される（下記）ため、投稿完了直前ではなく
  投稿画面を開いた時点で先読みしておくことで、初回投稿時にボトルが欠けたり
  遅れて表示されたりしないようにしている。2回目以降はブラウザキャッシュが
  効くため、`openPost()`を呼ぶたびに実行しても無害

### 投稿写真の拡大縮小・移動調整

写真を選んだ後、正方形の写真枠（`.polaroid .photo`, `aspect-ratio:1/1`）の
中でピンチ拡大縮小・ドラッグ移動ができる。以前は選んだ写真を
`background-size:cover`で中央に自動配置するだけで、ユーザーは調整できな
かった。回転は一切実装していない（`transform:rotate`もジェスチャーも無く、
2本指操作は距離比だけを見てスケールに変換するため、角度成分はそもそも
計算に登場しない）。

**DOM構成**（`#post-photo`, [shor.html:700-707](../shor.html#L700-L707)）:
`.photo`直下に`#post-blur`（常に枠を`cover`で覆う固定のぼかし背景、
`filter:blur(20px)` + 縁漏れ防止の`scale(1.1)`、[shor.html:513-518]
(../shor.html#L513-L518)）と`#post-adjust`（実際に動かす`<img>`本体、
[shor.html:519-525](../shor.html#L519-L525)）を重ねている。`#post-photo`
自体は`touch-action:none`（[shor.html:512](../shor.html#L512)）でブラウザ
標準のスクロール/ズームを無効化し、ジェスチャーは全て自前実装する。

**状態とスケール範囲**（`adjust`変数、[shor.html:1244-1252]
(../shor.html#L1244-L1252)）: `{scale, tx, ty, minScale, maxScale, natW, natH}`
を1つのオブジェクトに保持し、`#post-adjust`は`transform:translate(tx,ty)
scale(scale)`（`transform-origin:0 0`）だけで位置・大きさを表す。

- 上限 `maxScale` はcover相当（枠を覆う最小倍率）の4倍
- 下限 `minScale` は**contain相当**（写真全体が枠に収まる最小倍率、長い辺が
  枠の一辺に一致する）: `containScale = box / max(natW, natH)`。以前の実装は
  下限がcover相当までしかなく、写真の一部を必ず切り取らざるを得なかった
- 初期値はcover相当（`coverScale = box / min(natW, natH)`）で中央配置。
  これは以前の「選ぶと自動でcoverに配置される」見た目を初期状態として
  引き継いだ形

`startAdjust(dataUrl)`（[shor.html:1273-1298](../shor.html#L1273-L1298)）が
画像選択直後にこの初期状態を計算し、`resetAdjust()`
（[shor.html:1300-1310](../shor.html#L1300-L1310)）が`resetPostForm()`から
呼ばれて調整状態（ズーム・位置・ぼかし背景・ジェスチャー状態）を初期化する
（撮り直し・送信完了後のフォームリセット時）。

**移動範囲のクランプ**（`clampAdjust()`, [shor.html:1254-1267]
(../shor.html#L1254-L1267)）: 軸ごとに独立して判定する。本体画像がその軸で
枠を覆っている（`natW*scale >= box`など）場合は「枠外に隙間が出ない範囲」で
自由に移動でき、枠より小さく余白がある場合はその軸を中央（
`tx = (box - natW*scale) / 2`、`ty`も同様）に固定する。以前は余白がある軸も
現在値をそのまま許容するクランプになっており、はみ出していない軸まで
ドラッグ位置がズレて見える不具合があった（修正済み）。

**ジェスチャー**（`snapshotGesture()`/`updateGesture()`,
[shor.html:1317-1354](../shor.html#L1317-L1354)、`pointerdown`/`pointermove`/
`pointerup`/`pointercancel`は[shor.html:1356-1374]
(../shor.html#L1356-L1374)）: ジェスチャー開始時点（指の本数が変わるたび）
の状態を1つのスナップショットに固定し、以後の`pointermove`はそこからの
差分で計算する（フレームごとの積み上げ誤差を避けるため）。1本指はドラッグ
（`tx`/`ty`を移動量ぶん加算）、2本指は指の距離の比だけをスケール変化に変換
し、ピンチの中点が指す画像上の点が常に同じ位置に留まるよう`tx`/`ty`を
再計算する（標準的なピンチズームの中心固定アンカー）。角度は一度も計算しない
ため、回転が混入する余地が構造的に無い。PC確認用に`wheel`イベントでの
ズームも付けてある（[shor.html:1377-1389](../shor.html#L1377-L1389)、任意
機能）。撮り直しボタン（`.pick.picked`、枠の右下に重なる）へのタップは
`e.target.closest(".pick")`で判定してジェスチャーとして拾わないようにして
いる。

**送信時の書き出し**（`cropAdjusted(outSize)`,
[shor.html:1394-1423](../shor.html#L1394-L1423)、`btn-send`から呼ばれる
[shor.html:1532](../shor.html#L1532)）: 元画像や位置情報は保存せず、
投稿画面で見えている見た目（ぼかし背景＋その上の本体写真）をそのまま
1枚の正方形JPEG（既定1080×1080）に焼き込んでアップロードする。手順は
canvasに(1)ぼかし背景を`.post-blur`と同じcover+`scale(1.1)`相当で全面描画
（`ctx.filter`でぼかす）→(2)本体写真を現在の`scale`/`tx`/`ty`をcanvas解像度
に換算した位置・大きさで重ねて描画、の2段階。これにより閲覧側で表示した
ときの見た目が投稿時と一致する。閲覧側（scr-viewの写真表示・現像インタ
ラクション）はこの変更の影響を受けない。

- 送信（`btn-send`）API成功後: `playSendoff()`
  （[shor.html:1559-1596](../shor.html#L1559-L1596)）を呼び、
  送り出し演出（下記）を再生してから`openDone()`を呼び、フォームを
  リセットする。API失敗時は演出を再生せず、エラー文言のみ表示する

### 投稿完了の送り出し演出（`playSendoff()`）

受け取り演出（scr-viewの`.unroll-stage`、[shor.html:206-318](../shor.html#L206-L318)）
と対になる、投稿完了時の演出。`.sendoff-stage`/`.sendoff-overlay`への
`play`クラス付与だけで全ての間合いをCSSアニメーションに任せており、
JS側は再生開始と合計`SENDOFF_TOTAL_MS`（6.8秒）後の後始末しか行わない
（`openDone()`呼び出し、`post-lead`・フォームのリセット）。演出中は
`.sendoff-overlay.play`が画面全体を覆う`position:fixed`要素として
`pointer-events:auto`になるため、操作はブロックされる
（[shor.html:320-436](../shor.html#L320-L436)）。

後始末は2段階に分かれている（`playSendoff()`,
[shor.html:1559-1596](../shor.html#L1559-L1596)）。`SENDOFF_TOTAL_MS`後、
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
   [shor.html:338-346](../shor.html#L338-L346)）の`clip-path`が
   `inset(0 0 4.5px 0)`→`inset(0 0 calc(100% - 13px) 0)`へ変化する
   （`sendoffRollUp`, [shor.html:387-390](../shor.html#L387-L390)）。
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
   `sendoffClipFinish`（[shor.html:393-396](../shor.html#L393-L396)）を
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
   （[shor.html:330-337](../shor.html#L330-L337)）も付けてある。受け取り
   演出側の`.polaroid-shadow`には`rotate(1.5deg)`があり、それが独立した
   合成レイヤーを作る副作用で`filter:drop-shadow`が子の`clip-path`アニメ
   ーションに毎フレーム正しく追従しているが、送り出し側の`.sendoff-shadow`
   にはtransformが無く、この差のせいで影がclip前の古い形状のまま描画され
   続け、筒より下にカードの影が薄いゴーストとして残って見えることがあった。
   `.sendoff-clip`側にも`will-change:clip-path`を付け、同様に正しいレイヤー
   化を促している。加えて`.sendoff-stage.play
   .polaroid{backdrop-filter:none;-webkit-backdrop-filter:none}`
   （[shor.html:356-359](../shor.html#L356-L359)）で演出中は
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
   [shor.html:720-722](../shor.html#L720-L722)）。`.sendoff-bottle`自体の
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
として表示している（`<p class="passage">`、[shor.html:731](../shor.html#L731)）。
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

- 表示関数: `openDone()`（[shor.html:1657](../shor.html#L1657)、投稿直後）
  / `backToDone()`（[shor.html:1658](../shor.html#L1658)、閲覧起点がdoneで
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
    [shor.html:1679-1713](../shor.html#L1679-L1713)）

## モーダル（画面遷移ではなく重ね表示）

`.screen`とは別に、現在の画面の上に重ねて出すモーダルが3つある
（`showModal()`/`hideModal()`, [shor.html:1718-1724](../shor.html#L1718-L1724)）。

- `result-modal`（投稿結果） — `withResultGate()`
  （[shor.html:1054-1061](../shor.html#L1054-L1061)）が、`pendingResults`
  （前日以前に投稿してまだ結果を見せていない投稿の配列、古い順）に
  1件以上あるときボタン操作をブロックして先に表示する。中身は
  `showNextResult()`（[shor.html:1063-1077](../shor.html#L1063-L1077)）が
  1件popして描画する:
  - `#result-sec`に秒数（`view_history.viewed_seconds`の合計、
    `getResultForPost()`で投稿単位に集計）
  - サムネイルがあれば`#result-thumb`に表示。無ければ非表示のまま
    （この機能を入れる前からの保留分は日付単位の合算で、サムネイルを
    持たないため秒数のみになる。[data-model.md](data-model.md)の
    「投稿結果表示用のローカルストレージ」参照）

  モーダルを閉じる（`closeResultModal()`, [shor.html:1726-1735](../shor.html#L1726-L1735)）
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
