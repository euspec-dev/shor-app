# 画面遷移

`shor.html`には4つの`.screen`セクションがあり、`show(id)`
（[shor.html:1085](../shor.html#L1085)）が`.active`クラスを付け替えることで
1画面だけを表示する（CSSのフェードは[shor.html:111-119](../shor.html#L111-L119)）。
現像インタラクション（長押し）そのものの詳細は
[develop-interaction.md](develop-interaction.md)を参照。

```
scr-home ──「浜辺を見に行く」（常時、写真が無ければ画面内で案内）──▶ scr-view ──現像完了(origin=home)──▶ scr-post
   │                                                                     │
   └──「写真を流す」（常時固定）────────────────────────────────────────────┘
                                                                       canView()時「流れ着いた一通を見る」
                                                                       （origin=post）からも到達できる
scr-post ──送信──▶ scr-done ──「流れ着いた一通を見る」──▶ scr-view ──現像完了(origin=done)──▶ scr-home（戻らない）
scr-view（写真が無い状態）──「ホームへ」──▶ scr-home
scr-post/scr-done「ホームへ」・canView()falseの`post-to-top` ──▶ scr-home
```

`origin`（`"home"`/`"post"`/`"done"`）は`openView()`の引数で、現像完了後に
どちらへ戻るかを決める（下記scr-view節参照）。scr-home⇄scr-postの間に
scr-viewへの入り口が2つ（home起点/post起点）ある。home起点だけは
`canView()`の可否を問わず常に遷移でき、写真が用意できない場合は
scr-view内でその旨を案内する（下記scr-view節「写真が無い状態」参照）。

## レイアウトのレスポンシブ対応

4画面（ホーム・投稿・受け取り・完了）いずれも、画面高600px〜950px・
主要3機種（iPhone SE相当375×667、iPhone 15相当393×852、Android標準
412×915）・Safari/Chromeのアドレスバー表示/非表示（実質的に画面高が
50〜80px変動する）の組み合わせで、スクロール無しに全要素が収まることを
Playwrightで実測して確認している。`body{overflow:hidden}`（意図的な
no-scroll設計）のため、はみ出しは「隠れて見えなくなる」だけで、スクロール
して見ることはできない。

- **ビューポート高さ**: `#app`は`height:100vh`を先に書き、`height:100dvh`
  で上書きする（[shor.html:107](../shor.html#L107)）。`dvh`はモバイル
  ブラウザのアドレスバー表示/非表示に追従する動的単位、`vh`は非対応
  ブラウザ向けのフォールバック。以降に追加した`clamp()`/`calc()`も含め、
  画面高を参照する箇所は全て`dvh`を使っている
- **セーフエリア**: `#app`のpadding-bottom（`calc(60px + env(safe-area-inset-bottom))`、
  [shor.html:109](../shor.html#L109)）・footer・`#whisper`が
  `env(safe-area-inset-bottom)`を加算済み。iPhoneのホームインジケータ
  領域を避ける
- **フッターの重なり**: footerは`position:fixed`のまま
  （[shor.html:234](../shor.html#L234)）変更していない。`#app`の
  padding-bottom（60px+セーフエリア）が元々footerの表示域を確保して
  いるため、`.screen`側のコンテンツが`max-height:100%`
  （[shor.html:116](../shor.html#L116)）に収まりさえすれば理屈上
  footerと重ならない。実際にはflexboxは子要素を自動では縮めないため、
  以下のclamp()/calc()で各画面のコンテンツ自体を縮めることで
  この前提を成立させている（「フッターと重ならないよう個別に余白を
  確保する」のではなく、「そもそもmax-height内に収まるようにする」
  方針）
- **画面高に応じて可変にした値**（すべて`clamp(MIN, calc(MIN + 差分 *
  ((100dvh - 600px) / 350px)), MAX)`の形。600px以下でMIN、950px以上でMAX、
  間は線形補間）:
  - `p.passage`の`line-height`（2→1.7）・段落間`margin-top`（2em→1.3em、
    [shor.html:126-131](../shor.html#L126-L131)）
  - `.theme-note`の`margin-bottom`（1.8em→1em、[shor.html:140-141](../shor.html#L140-L141)）
  - `#home-to-post`の`margin-top`（3em→1.6em、[shor.html:170](../shor.html#L170)）・
    `.btn.secondary`の`margin-top`（1.2em→.5em、[shor.html:208-209](../shor.html#L208-L209)）
  - `.done-actions`の`margin-top`（3.2em→1.8em、[shor.html:213-214]
    (../shor.html#L213-L214)）・`.done-foot`の`padding-top`（3.4em→1.8em、
    [shor.html:223-224](../shor.html#L223-L224)）・`.btn.done-pwa`の
    `margin-top`（1.6em→.8em、[shor.html:226-227](../shor.html#L226-L227)）
  - `.screen-note`の`padding-top`（16px→8px、[shor.html:558-560]
    (../shor.html#L558-L560)）・`.to-top`の`padding-top`（30px→14px、
    [shor.html:563-565](../shor.html#L563-L565)）
- **ポラロイドの高さ基準サイズ**: `#post-polaroid`・`#view-polaroid`は
  それぞれ`width:min(Nvw, Npx, calc(100dvh - Mpx))`の第3項で、画面幅では
  なく利用可能な高さを基準にサイズを決める（正方形の写真枠
  `aspect-ratio:1/1`が縦幅の大半を占めるため、幅を絞ると高さも絞れる）。
  画面高が十分あるときは`vw`/`px`の上限が効き、厳しいときだけこの項が
  効く。詳細・定数の内訳は各画面節の「投稿写真の拡大縮小・移動調整」
  「巻紙が開く演出」を参照
- 背景写真（`#shore`）・全体の世界観に関わるCSSは変更していない。
  今回はすべて余白・サイズの調整で対応した

## scr-home（画面1: ダッシュボード）

- 表示関数: `renderHome()`（[shor.html:1175-1225](../shor.html#L1175-L1225)）
- 呼ばれるタイミング: 起動時、および各画面の「ホームへ」
  （`post-to-top`が`canView()`falseのとき, `done-to-top`）
- `pendingResults`（前日以前の投稿で未確認の結果、配列）は毎回計算するが、
  自動でモーダルを出す・画面遷移をブロックすることはしない
  （`withResultGate()`は廃止済み）。結果は下記「しらせ帯」からのみ開く

DOM上の並び順は `#home-a`（説明文、常時） → `#home-notice`（しらせ帯） →
`#home-to-post`（主ボタン、常時） → `#btn-see`（副ボタン、常時）。主・副
ボタンは間隔を詰めて1組のペアに見せる（下記「主・副ボタン」参照）。
テーマ表示はホームには置かない（投稿画面・閲覧画面のみに表示、
[data-model.md](data-model.md)の「投稿テーマ」参照）。

### 説明文（`#home-a`）

`myPosts`の空・非空にかかわらず常時表示する（新しいlocalStorageキーは
追加していない）。以前は初回訪問時（`myPosts`が空）だけの表示だったが、
毎回表示するよう変更した。4段落構成で、段落の区切りは変えていない。

1〜2段落目（`.home-a-rise`クラス、[shor.html:133](../shor.html#L133)）だけ
`position:relative;top:-32px`で視覚的に上へずらしてある。背景写真
（`#shore`）の水平線と文章が重なって読みにくい問題への対応で、
`position:relative`はレイアウト上の占有幅を変えないため、3・4段落目や
ボタンの位置には影響しない（32pxという値は393×852相当の画面での見え方を
基準にした目算で、画面サイズによって重なり方が変わる点は残る）。

常時表示になったことで、`#home-a`＋`#home-notice`（しらせ帯）＋主・副
ボタンが同時に表示される状態（投稿済み、かつ未確認の結果あり）が縦方向に
最も長くなる。`p.passage`の行間・段落間余白、`#home-to-post`/
`.btn.secondary`の`margin-top`が画面高に応じてclamp()で縮む点は上記
「レイアウトのレスポンシブ対応」節を参照。それに加え、しらせ帯が実際に
表示されているときだけ主ボタンの上マージンをさらに`.1em`まで詰める
`.notice-strip:not([hidden]) + #home-to-post`（[shor.html:175]
(../shor.html#L175)）を用意した（画面高に関わらず一律`.1em`で、
最も縦に長くなるこの状態専用の追加の詰め）。文言の短縮・削除では
対応していない。

### 主・副ボタン（`#home-to-post` / `#btn-see`）

- 両ボタンとも`width:190px`で幅を揃えている（[shor.html:210]
  (../shor.html#L210)）。文言の長さが違う（「写真を流す」/「浜辺を見に
  行く」）ため、幅を明示しないと自然幅で揃わない
- `#home-to-post`「写真を流す」: 常時表示・文言固定。クリックで`openPost()`
  を直接呼ぶ（[shor.html:1910](../shor.html#L1910)、`withResultGate`の
  ラップは廃止）
- `#btn-see`「浜辺を見に行く」: 常時表示・常時押下可能・文言固定（以前は
  `myPosts`/`canView()`で文言と`disabled`を出し分けていたが廃止）。
  `#home-to-post`と同じ`.btn`の見た目のまま、枠線の不透明度だけ下げて
  （`.btn.secondary`、[shor.html:208-209](../shor.html#L208-L209)）従属して
  見せている。`margin-top`は`.btn.secondary`側で画面高600px〜950pxの
  clamp()により`.5em`〜`1.2em`の範囲で可変にし、主ボタンとの間隔を保ちつつ
  1組のペアに見せている。クリックで無条件に`openView("home")`する
  （[shor.html:2014](../shor.html#L2014)）。
  `canView()`が`false`のとき、および候補が無いときの案内は、ここでは行わず
  `openView()`側・閲覧画面に入ってから画面内で行う
  （下記scr-view節「写真が無い状態」参照）

### しらせ帯（`#home-notice`）

`#home-a`の下、主・副ボタン対の上に表示する。未確認の結果
（`pendingResults`）が1件以上あるときだけ表示し、無い日は`hidden`で
ブロックごと非表示にする（初回ユーザー・未確認が無い日は一切出さない）。

- サムネイルは`pendingResults`のうち`thumb`を持つものを古い順に最大3件
  （`.notice-strip-thumbs`に丸いサムネイルを重ねて並べる）。日付単位の
  レガシー保留分は`thumb`が無いためサムネイルに含まれない
- 秒数はここには出さない。タップするまで伏せる
- タップで`showNextResult()`を呼び、`result-modal`を開く
  （[shor.html:1911](../shor.html#L1911)。既存の関数をそのまま使う。
  下記「結果モーダル」節参照）
- `noticeStripPulse`という`opacity:.55⇔1`のCSSアニメーション（2.6s、
  `ease-in-out infinite`）を常時付けており、点滅ではなく透明度が緩やかに
  上下する「呼吸」のような見た目で目立たせている。世界観に合わせ急激な
  変化は避けた。`hidden`（`display:none`）の間はアニメーションも走らない。
  `prefers-reduced-motion: reduce`はCSS側の既存のグローバル無効化ルールで
  カバーされる（個別対応は不要）

## scr-view（画面2: 閲覧/現像）

- 表示関数: `openView(origin, forcedDrift)`（[shor.html:1244]
  (../shor.html#L1244)）。`origin`は`"home"`/`"post"`/`"done"`で、現像後に
  どちらへ戻るかを覚えておくために使う。`forcedDrift`は省略可能で、開発
  バーの「テーマ閲覧」専用（[data-model.md](data-model.md)の「投稿テーマ」
  参照）。指定時は`peek_drift`も閲覧枠チェックも丸ごとスキップする

### 写真が無い状態

`origin === "home"`（`#btn-see`「浜辺を見に行く」から）のときだけ、
`peek_drift`すら呼ばずに閲覧枠切れを判定でき、かつ候補0件・画像読み込み
失敗も含めて**画面遷移せずscr-view内で案内する**。`post`/`done`は
呼び出し元で`canView()`を確認済みでこの関数に来る（`post`は`canView()`
`true`のときだけ`openView("post")`を呼び、`done`は`btn-give2see`側で
`notice-modal`に弾く）ため、home以外はここでは分岐しない。

1. **閲覧枠が無い**（`canView()`が`false`、[shor.html:1276-1279]
   (../shor.html#L1276-L1279)）: `peek_drift`を呼ばずに`showViewEmpty()`
   で「明日の朝　潮が満ちるころに届きます」（「明日の朝」と「潮が満ちる
   ころに」の間は全角スペース1つ）を表示する
2. **候補が0件、または画像読み込みに失敗**（ストレージから画像が手動削除
   された直後など、`imageLoads()`で先読みチェックしている
   [shor.html:1251-1258](../shor.html#L1251-L1258) / [shor.html:1296]
   (../shor.html#L1296)）: home起点なら`showViewEmpty()`で「まだ、流れ着いた
   一枚がありません／あなたが最初の一人になりませんか」を表示する
   （[shor.html:1304-1307](../shor.html#L1304-L1307)）。post/doneはこれまで
   通り、まず`origin==="done"`なら`backToDone()`、それ以外は`renderHome()`
   で先に画面を戻してから`notice-modal`（[shor.html:1308-1309]
   (../shor.html#L1308-L1309)）で同じ文言を知らせる（壊れた画像をそのまま
   表示することはない）。以前は画面下部固定の`whisper()`を使っていたが、
   `backToDone()`で投稿完了画面に戻った直後だと同じく画面下部にある
   `#pwa-note`（PWA案内）と文字が重なる事故があったため、先に画面遷移を
   済ませてからモーダルで知らせる方式に変更した

`showViewEmpty(html)`（[shor.html:1343-1348](../shor.html#L1343-L1348)）は
`.unroll-stage`と`#view-screen-note`を`hidden`にし、`#view-empty`
（`#view-empty-text`＋「ホームへ」の`.to-top`ボタン）を表示するだけで、
`#shore`/`#veil`（背景の砂浜・波の演出）自体には触れない。**モーダルでは
なくscr-view内の表示**なので、`#view-empty-to-top`のクリックで
`renderHome()`を呼ぶ以外に離脱手段が無いことに注意
（[shor.html:1349](../shor.html#L1349)。scr-viewはこれまで候補が無い時に
表示されること自体が無かったため、専用の「ホームへ」導線が必要になった）。

- 候補の取得に成功すると、写真がすぐには見えず前置き演出を挟む
  （[shor.html:1324-1337](../shor.html#L1324-L1337)）:
  1. 1250ms後、前置きメッセージ「誰かのボトルメールが、流れ着きました」がフェードイン
  2. 3300ms後、そのメッセージがフェードアウトし始める
  3. 4500ms後（メッセージのフェードアウトが完全に終わってから）、
     「ひもで結ばれた巻紙がほどけてポラロイドが開く」演出を開始する
     （`.unroll-stage`に`play`クラスを追加）
- `drift.theme`が存在すれば、`.unroll-stage`の外側・上に置いた
  `#view-theme`（`.theme-note`、[data-model.md](data-model.md)の
  「投稿テーマ」参照）に投稿日（`drift.created_at`を`M月D日`形式に整形）
  とテーマ文言を表示する。表示タイミングは上記3の巻紙が開き始める瞬間に
  揃えており（中身の設定自体はもっと早い、写真URL設定と同じタイミングで
  行うが、`hidden`を外すのは巻紙の`play`クラス付与と同時）、`theme`が
  `null`（テーマ追加前の投稿・シード投稿）ならブロックごと非表示のまま
- `#view-polaroid`は`.polaroid`共通の`width:min(86vw,350px)`を
  `width:min(76vw,315px,calc(100dvh - 385px))`で上書きしている
  （[shor.html:259](../shor.html#L259)）。`.unroll-stage`自体の幅
  （[shor.html:289](../shor.html#L289)）も同じ値に合わせてあるが、
  `#view-polaroid`は`.polaroid`の幅指定を直接持つため、`.unroll-stage`側
  だけを変えても追従しない点に注意（両方の指定が必要）。第3項
  `calc(100dvh - 385px)`は「利用可能な画面高から、写真以外に必要な高さ
  （テーマ・キャプション行・裾・戻る導線・上下余白など）を差し引いた
  残り」を表す目安で、画面高が十分あるときは`76vw`/`315px`の上限が効き、
  画面高が厳しいとき（アドレスバー表示時など）だけこの項が効いて正方形の
  写真枠ごと縮む（幅基準ではなく高さ基準でサイズが決まる）。385という
  定数はiPhone SE相当（375×667）〜Android標準（412×915）、画面高
  600px（下限の目安）〜950px、Safari/Chromeのアドレスバー表示/非表示の
  組み合わせで実測して調整した値（「レイアウトのレスポンシブ対応」節参照）
- 巻紙が開く演出（`.unroll-stage`, [shor.html:284-396](../shor.html#L284-L396)）は、
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
    値で動く（[shor.html:375-378](../shor.html#L375-L378)）。以前はこの補正が
    無く、単純に`100%`⇔`0`だったため、常に筒の中心と開口端が最大13pxずれて
    見える不具合があった
  - `rollGo`のopacityは以前は`top`/`height`と同じキーフレーム内（86%地点）
    に同居していたが、それだけのために86%でキーフレームが増え、25%区間の
    イージング指定が86%以降は既定の`ease`に戻ってしまい、後半で筒とカードの
    動きが分離するバグがあった。opacityは`rollFade`という別animationに
    分離し、`rollGo`の25%→100%区間は単一のイージングのまま`sheetOpen`と
    完全に同期させている
  - 演出中（`.rolling`クラスが付いている間、[shor.html:312](../shor.html#L312)、
    JS側は[shor.html:1329-1337](../shor.html#L1329-L1337)）は`.frost`の
    `backdrop-filter`を無効化する。WebKitは`backdrop-filter`を持つ要素の
    背景ぼかし層を祖先の`clip-path`で切り取れないことがあり、無効化しないと
    巻紙が完全に閉じていてもぼかしガラス層だけが筒の外にはみ出て見えることが
    ある。ただし`#view-polaroid`は演出後も現像インタラクションで
    `.frost`のぼかしを使い続けるため、`.play`とは別に`.rolling`という
    演出専用クラスを設け、巻紙が開き切る頃（演出開始から4.1s後）にJSで
    外して元に戻している
  - `.polaroid-clip`は`clip-path`に`round`を付けず、`overflow:hidden`＋
    静的な`border-radius:2px`だけで角丸を担う（[shor.html:272-279]
    (../shor.html#L272-L279)）。`round`付きの`clip-path`をアニメーション
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
    即座に切り替える（[shor.html:392-396](../shor.html#L392-L396)）
  - フェードイン/アウトの所要時間そのもの（前置きメッセージ・ホーム→scr-viewの
    画面遷移）は共通の`--dur-fade`（1100ms、[shor.html:52](../shor.html#L52)）を
    使っている。`--dur-fade-photo`（1600ms、[shor.html:53](../shor.html#L53)）は
    現在ポラロイドの登場には使われておらず、`washed`クラスによる退出（波に
    さらわれる）アニメーションにのみ使われている（[shor.html:270](../shor.html#L270)）
  - 上記の1250/3300/4500msは、あくまで「いつ演出を開始するか」のタイミング
- 現像インタラクション完了（長押しをやり切って指を離す）後、washのアニメーション
  を経て:
  - `origin==="done"`（[shor.html:1428](../shor.html#L1428)）→ `renderHome()`
    （→scr-home）。投稿完了画面経由で見た場合も、現像後は投稿完了画面には
    戻らずホームへ抜ける（意図的な仕様。「候補0件」で見られなかった場合の
    `backToDone()`分岐（[shor.html:1308](../shor.html#L1308)）とは扱いが違う点に注意）
  - それ以外 → `openPost()`（[shor.html:1429](../shor.html#L1429)、→scr-post）。
    `origin`が`"post"`（scr-postから直接見に来た場合）もこちらに含まれる
- 長押しを最後までやり切らずに離した場合はこの画面に留まり、同じ写真に
  再挑戦できる（`resetDevelop(false)`、[develop-interaction.md](develop-interaction.md)参照）

## scr-post（画面3: 投稿）

- 表示関数: `openPost()`（[shor.html:1646-1667](../shor.html#L1646-L1667)）
- 呼ばれるタイミング: scr-homeの「写真を流す」、scr-viewでの現像完了後
  （閲覧起点がhomeの場合）、scr-doneの「もう一枚流す」
  （`btn-post-again`）
- `openPost()`は`show("scr-post")`の直後に`new Image().src = "bottle.png"`
  で送り出し演出用のボトル画像を先読みする（同ファイル内）。ボトルは演出
  開始から約3.2秒後に初めて表示される（下記）ため、投稿完了直前ではなく
  投稿画面を開いた時点で先読みしておくことで、初回投稿時にボトルが欠けたり
  遅れて表示されたりしないようにしている。2回目以降はブラウザキャッシュが
  効くため、`openPost()`を呼ぶたびに実行しても無害
- 以前あった`#post-lead`（リード文「今度はこっそりと、あなたの感性を
  誰かに届けてみませんか？」）は、ホーム画面の説明文（`#home-a`）と役割が
  重複するため撤去した。関連する表示/非表示切り替え（送信時のフェード等）
  もJS側から丸ごと削除している
- `#post-polaroid`の外側・上（`#sendoff-stage`の直前）に`#post-theme`
  （`.theme-note`）があり、`openPost()`が毎回`themeFor()`
  （引数省略＝今日、[data-model.md](data-model.md)の「投稿テーマ」参照）
  の結果を「今日のテーマ／「（テーマ文言）」」の形で設定する。常に今日の
  投稿の分なので、受け取り側と違って非表示になることはない
- 戻る導線（`post-to-top`）は`openPost()`が毎回`canView()`を見て文言を
  切り替える。`true`なら「流れ着いた一通を見る」で押すと`openView("post")`
  （→scr-view）、`false`なら「ホームへ」で押すと`renderHome()`
  （[shor.html:1904-1908](../shor.html#L1904-L1908)）。DOM上は
  `#sendoff-overlay`の直後（画面の一番下）にあり、`#post-polaroid`の
  すぐ下・フッターの上に位置する
- `myPosts`が空（一度も投稿していない）のときだけ、`#post-photo`に
  `#post-dummy`（薄い見本写真＋見本キャプション、`DUMMY_PHOTO_URL`/
  `DUMMY_CAPTION`定数、[shor.html:973-976](../shor.html#L973-L976)。
  いずれも仮の値で、本番実装時に差し替え用の画像・文言を要確認）を重ねる。
  `pointer-events:none`なので`btn-pick`の操作は妨げない。実際に写真を
  選ぶと`handlePickedFile()`が`#post-dummy`を`hidden`にする
  （[shor.html:1742](../shor.html#L1742)）。ダミー画像・キャプションは
  `pickedDataUrl`/`adjust`を一切経由しない別要素のため、送信データに
  含まれることは構造的に無い
- キャプション欄（`#cap-input`）は`maxlength="15"`だが、IME変換中の
  未確定文字列にはこの属性が効かないため、変換確定後（`compositionend`）と
  通常入力時（`input`、非変換中のみ）に`enforceCapLimit()`
  （[shor.html:1676-1679](../shor.html#L1676-L1679)）が`[...value]`基準
  （サロゲートペア対応）で15文字を超えた分を切り詰める。`postValid()`
  （[shor.html:1669-1672](../shor.html#L1669-L1672)）も同じ`[...value]`基準
  で15文字以下を要求する
- カウンター（`#cap-counter`）は常時表示（`0/15`形式）。以前あった
  「残り5文字を切ってから表示」（`.show`クラスでのフェードイン）は撤去した。
  上限超過時の色変化（`.over`クラス）も、`enforceCapLimit()`により実質
  超過が起き得なくなったため撤去した（`refreshPostUI()`,
  [shor.html:1680-1684](../shor.html#L1680-L1684)）

### 投稿写真の拡大縮小・移動調整

`#post-polaroid`は`.polaroid`共通の`width:min(86vw,350px)`を
`width:min(78vw,320px,calc(100dvh - 330px))`で上書きしている
（[shor.html:258](../shor.html#L258)）。第3項`calc(100dvh - 330px)`は
`#view-polaroid`と同じ考え方（利用可能な画面高から写真以外に必要な高さを
差し引いた残り）で、画面高が厳しいときだけ効いて正方形の写真枠
（`aspect-ratio:1/1`）ごと縮む。テーマ表示・ポラロイド・送信ボタン・戻る
導線（`post-to-top`）までが画面高600px〜950pxの範囲でスクロールなしに
収まるようにするための調整（詳細は「レイアウトのレスポンシブ対応」節参照）。

写真を選んだ後、正方形の写真枠（`.polaroid .photo`, `aspect-ratio:1/1`）の
中でピンチ拡大縮小・ドラッグ移動ができる。以前は選んだ写真を
`background-size:cover`で中央に自動配置するだけで、ユーザーは調整できな
かった。回転は一切実装していない（`transform:rotate`もジェスチャーも無く、
2本指操作は距離比だけを見てスケールに変換するため、角度成分はそもそも
計算に登場しない）。

**DOM構成**（`#post-photo`, [shor.html:817-828](../shor.html#L817-L828)）:
`.photo`直下に`#post-blur`（常に枠を`cover`で覆う固定のぼかし背景、
`filter:blur(20px)` + 縁漏れ防止の`scale(1.1)`、[shor.html:577-581]
(../shor.html#L577-L581)）と`#post-adjust`（実際に動かす`<img>`本体、
[shor.html:596-602](../shor.html#L596-L602)）、`#post-dummy`（見本表示、
上記参照）を重ねている。`#post-photo`自体は`touch-action:none`
（[shor.html:589](../shor.html#L589)）でブラウザ標準のスクロール/ズームを
無効化し、ジェスチャーは全て自前実装する。

**状態とスケール範囲**（`adjust`変数、[shor.html:1439-1443]
(../shor.html#L1439-L1443)）: `{scale, tx, ty, minScale, maxScale, natW, natH}`
を1つのオブジェクトに保持し、`#post-adjust`は`transform:translate(tx,ty)
scale(scale)`（`transform-origin:0 0`）だけで位置・大きさを表す。

- 上限 `maxScale` はcover相当（枠を覆う最小倍率）の4倍
- 下限 `minScale` は**contain相当**（写真全体が枠に収まる最小倍率、長い辺が
  枠の一辺に一致する）: `containScale = box / max(natW, natH)`。以前の実装は
  下限がcover相当までしかなく、写真の一部を必ず切り取らざるを得なかった
- 初期値はcover相当（`coverScale = box / min(natW, natH)`）で中央配置。
  これは以前の「選ぶと自動でcoverに配置される」見た目を初期状態として
  引き継いだ形

`startAdjust(dataUrl)`（[shor.html:1481-1506](../shor.html#L1481-L1506)）が
画像選択直後にこの初期状態を計算し、`resetAdjust()`
（[shor.html:1508-1518](../shor.html#L1508-L1518)）が`resetPostForm()`から
呼ばれて調整状態（ズーム・位置・ぼかし背景・ジェスチャー状態）を初期化する
（撮り直し・送信完了後のフォームリセット時）。

**移動範囲のクランプ**（`clampAdjust()`, [shor.html:1462-1475]
(../shor.html#L1462-L1475)）: 軸ごとに独立して判定する。本体画像がその軸で
枠を覆っている（`natW*scale >= box`など）場合は「枠外に隙間が出ない範囲」で
自由に移動でき、枠より小さく余白がある場合はその軸を中央（
`tx = (box - natW*scale) / 2`、`ty`も同様）に固定する。以前は余白がある軸も
現在値をそのまま許容するクランプになっており、はみ出していない軸まで
ドラッグ位置がズレて見える不具合があった（修正済み）。

**ジェスチャー**（`snapshotGesture()`/`updateGesture()`,
[shor.html:1525-1562](../shor.html#L1525-L1562)、`pointerdown`/`pointermove`/
`pointerup`/`pointercancel`は[shor.html:1564-1582]
(../shor.html#L1564-L1582)）: ジェスチャー開始時点（指の本数が変わるたび）
の状態を1つのスナップショットに固定し、以後の`pointermove`はそこからの
差分で計算する（フレームごとの積み上げ誤差を避けるため）。1本指はドラッグ
（`tx`/`ty`を移動量ぶん加算）、2本指は指の距離の比だけをスケール変化に変換
し、ピンチの中点が指す画像上の点が常に同じ位置に留まるよう`tx`/`ty`を
再計算する（標準的なピンチズームの中心固定アンカー）。角度は一度も計算しない
ため、回転が混入する余地が構造的に無い。PC確認用に`wheel`イベントでの
ズームも付けてある（[shor.html:1585-1597](../shor.html#L1585-L1597)、任意
機能）。撮り直しボタン（`.pick.picked`、枠の右下に重なる）へのタップは
`e.target.closest(".pick")`で判定してジェスチャーとして拾わないようにして
いる。

**送信時の書き出し**（`cropAdjusted(outSize)`,
[shor.html:1602-1631](../shor.html#L1602-L1631)、`btn-send`から呼ばれる
[shor.html:1768](../shor.html#L1768)）: 元画像や位置情報は保存せず、
投稿画面で見えている見た目（ぼかし背景＋その上の本体写真）をそのまま
1枚の正方形JPEG（既定1080×1080）に焼き込んでアップロードする。手順は
canvasに(1)ぼかし背景を`.post-blur`と同じcover+`scale(1.1)`相当で全面描画
（`ctx.filter`でぼかす）→(2)本体写真を現在の`scale`/`tx`/`ty`をcanvas解像度
に換算した位置・大きさで重ねて描画、の2段階。これにより閲覧側で表示した
ときの見た目が投稿時と一致する。閲覧側（scr-viewの写真表示・現像インタ
ラクション）はこの変更の影響を受けない。

- 送信（`btn-send`）API成功後: `playSendoff()`
  （[shor.html:1794-1825](../shor.html#L1794-L1825)）を呼び、
  送り出し演出（下記）を再生してから`openDone()`を呼び、フォームを
  リセットする。API失敗時は演出を再生せず、エラー文言のみ表示する

### 投稿完了の送り出し演出（`playSendoff()`）

受け取り演出（scr-viewの`.unroll-stage`、[shor.html:284-396](../shor.html#L284-L396)）
と対になる、投稿完了時の演出。`.sendoff-stage`/`.sendoff-overlay`への
`play`クラス付与だけで全ての間合いをCSSアニメーションに任せており、
JS側は再生開始と合計`SENDOFF_TOTAL_MS`（6.8秒）後の後始末しか行わない
（`openDone()`呼び出し、フォームのリセット）。演出中は
`.sendoff-overlay.play`が画面全体を覆う`position:fixed`要素として
`pointer-events:auto`になるため、操作はブロックされる
（[shor.html:398-514](../shor.html#L398-L514)）。

後始末は2段階に分かれている（`playSendoff()`,
[shor.html:1794-1825](../shor.html#L1794-L1825)）。`SENDOFF_TOTAL_MS`後、
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
   [shor.html:416-424](../shor.html#L416-L424)）の`clip-path`が
   `inset(0 0 4.5px 0)`→`inset(0 0 calc(100% - 13px) 0)`へ変化する
   （`sendoffRollUp`, [shor.html:465-468](../shor.html#L465-L468)）。
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
   `sendoffClipFinish`（[shor.html:471-474](../shor.html#L471-L474)）を
   `sendoffRollUp`と並べて重ね、`sendoffTubeFade`と全く同じ`.5s ease 2.7s`
   で残り13pxを`inset(0 0 100% 0)`（完全に閉じ切る）まで動かしている。
   筒が透明になり切るタイミングと、カードが完全に見えなくなるタイミングが
   一致するため、帯が浮いて見えることはない（`round`修飾は付けていない。
   角丸はここではなく`.sendoff-clip`の`overflow:hidden`+`border-radius:2px`
   （静的）だけが担う。`round`付きclip-pathをアニメーションさせると
   ブラウザによっては角丸矩形の再計算が毎フレーム正しく行われず、筒より
   下にカードが薄く残って見えることがあるため、アニメ対象のclip-pathから
   はroundを外し、角丸をoverflow:hidden側に一本化した）。`#post-polaroid`
   自身の`box-shadow`（`.polaroid`, [shor.html:247-248](../shor.html#L247-L248)）も
   この`overflow:hidden`で同じ境界に収まる。

   `.sendoff-shadow`には見た目に影響しない`transform:translateZ(0)`
   （[shor.html:408-415](../shor.html#L408-L415)）も付けてある。受け取り
   演出側の`.polaroid-shadow`には`rotate(1.5deg)`があり、それが独立した
   合成レイヤーを作る副作用で`filter:drop-shadow`が子の`clip-path`アニメ
   ーションに毎フレーム正しく追従しているが、送り出し側の`.sendoff-shadow`
   にはtransformが無く、この差のせいで影がclip前の古い形状のまま描画され
   続け、筒より下にカードの影が薄いゴーストとして残って見えることがあった。
   `.sendoff-clip`側にも`will-change:clip-path`を付け、同様に正しいレイヤー
   化を促している。加えて`.sendoff-stage.play
   .polaroid{backdrop-filter:none;-webkit-backdrop-filter:none}`
   （[shor.html:434-437](../shor.html#L434-L437)）で演出中は
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
   [shor.html:841-843](../shor.html#L841-L843)）。`.sendoff-bottle`自体の
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
として表示している（`<p class="passage">`、[shor.html:852](../shor.html#L852)）。
これにより演出の総時間も10秒から6.8秒に短縮された。

`prefers-reduced-motion: reduce`環境では、`.sendoff-stage.play`を
`display:none`にしてポラロイドの巻き上げ演出をスキップする。メッセージ
文言はscr-done側の常設テキストとして表示されるため、演出用のフォール
バック表示は不要になった。ボトルは元々装飾用で、CSSの初期値
`opacity:0`のまま、グローバルなアニメーション無効化ルールに従って
非表示になる。**スコープは`.play`中に限定**しており、投稿前の
写真選択中の表示（`.sendoff-stage`は常設）まで消えないよう注意している。

- `post-to-top`は`canView()`で分岐する（詳細は上記「投稿画面の戻る導線」）:
  `true`なら「流れ着いた一通を見る」→`openView("post")`（→scr-view）、
  `false`なら「ホームへ」→`renderHome()`（→scr-home）

## scr-done（画面4: 投稿完了）

- 表示関数: `openDone()`（[shor.html:1886](../shor.html#L1886)、投稿直後）
  / `backToDone()`（[shor.html:1887-1894](../shor.html#L1887-L1894)、閲覧起点がdoneで
  かつ候補0件だったときのみ使用。`done-body`のpendingクラスを一旦外して
  再アニメーションできる状態に戻す。現像を最後までやり切った場合は
  `renderHome()`でscr-homeに抜けるため、この関数は呼ばれない）
- ボタン:
  - `btn-give2see`「流れ着いた一通を見る」→ `canView()`が`false`なら
    `notice-modal`、`true`なら`openView("done")`（→scr-view、
    ここでの`origin`は`"done"`。現像を最後までやり切った場合はscr-doneには
    戻らずscr-homeへ抜ける。候補0件で見られなかった場合のみscr-doneに戻る）
  - `btn-post-again`「もう一枚流す」→ `openPost()`（→scr-post）
  - `done-to-top`「ホームへ」→ `renderHome()`（→scr-home）
  - `btn-pwa`「ホーム画面に追加する」→ PWAインストールプロンプト
    （`beforeinstallprompt`が発火していれば）、無ければ操作手順を
    ボタンの下の`#pwa-help`（ボタン上の`#pwa-note`とは別要素）に一時表示する。
    `whisper()`は固定位置でscr-doneのようなコンテンツの多い画面だと
    ボタンと重なるため使っていない。`#pwa-help`は`position:absolute`で
    通常のレイアウトの高さ計算に参加しないようにしてあり、押下前後で
    `#pwa-note`やボタンの位置が動かないようにしている
    （[shor.html:218-231](../shor.html#L218-L231)、JS側は
    [shor.html:1913-1947](../shor.html#L1913-L1947)）

## モーダル（画面遷移ではなく重ね表示）

`.screen`とは別に、現在の画面の上に重ねて出すモーダルが3つある
（`showModal()`/`hideModal()`, [shor.html:1986-1992](../shor.html#L1986-L1992)）。

- `result-modal`（投稿結果） — 以前は`withResultGate()`が`pendingResults`
  （前日以前に投稿してまだ結果を見せていない投稿の配列、古い順）を見て
  ボタン操作をブロックし自動的に開いていたが、この仕組みは廃止した。
  現在は**scr-homeの「しらせ帯」（`#home-notice`）をタップしたときだけ**
  開く（上記scr-home節参照）。中身は`showNextResult()`
  （[shor.html:1227-1241](../shor.html#L1227-L1241)）が`pendingResults`から
  1件popして描画する:
  - `#result-sec`に秒数（`view_history.viewed_seconds`の合計、
    `getResultForPost()`で投稿単位に集計）
  - サムネイルがあれば`#result-thumb`に表示。無ければ非表示のまま
    （この機能を入れる前からの保留分は日付単位の合算で、サムネイルを
    持たないため秒数のみになる。[data-model.md](data-model.md)の
    「投稿結果表示用のローカルストレージ」参照）

  **まだ誰にも見られていない投稿は、そもそも`pendingResults`に積まれない**
  （`renderHome()`が`getResultForPost()`/`getResultForDate()`の戻り値が
  `null`（＝`view_history`に行が無い＝未閲覧）の投稿を無言でスキップする。
  [data-model.md](data-model.md)の該当節参照）。以前は未閲覧でも「0秒間
  見られました」という結果が出ていたが、これは配信期限を撤廃した設計
  （[distribution.md](distribution.md)の「配信期限を撤廃した理由」参照）と
  矛盾する——期限が無い以上、その投稿は後日まだ見られる可能性があるため。
  未閲覧の投稿は`resultConfirmed`フラグも立てずに次回以降の`renderHome()`へ
  先送りされ、実際に1人以上に見られた後、最初にアプリを開いたときに初めて
  結果が表示される。表示される秒数は必ず1秒以上になる。

  モーダルを閉じる（`closeResultModal()`, [shor.html:1994-1999](../shor.html#L1994-L1999)）
  たびに`pendingResults`が残っていれば次の1件を表示し、無くなって初めて
  閉じたままになる（以前あった「閉じた後に本来のアクションへ進む」
  `afterResultAction`の仕組みは、画面遷移を一切ブロックしなくなったため
  丸ごと廃止した）。一覧・履歴のようなUIは無く、常に「今見せる1件」だけを
  モーダルで順に見せる設計
- `notice-modal`（閲覧枠切れ等のお知らせ） — scr-doneの`btn-give2see`
  からのみ表示する。scr-homeの`#btn-see`（「浜辺を見に行く」）は常時
  押下可能で、閲覧枠切れ・候補0件のどちらもscr-view内の表示
  （上記scr-view節「写真が無い状態」参照）に置き換えたため、
  `notice-modal`を経由しない（詳細は[view-grants.md](view-grants.md)の
  「上限に達したときのUI」参照）
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

## 新しいバージョンの通知（`#update-banner`）

PWAをホーム画面から開くと、OSがネットワークに問い合わせず前回読み込んだ
ページをそのまま復元することがあり、デプロイ済みの新しいコードが端末に
反映されないことがある。`service-worker.js`は何もキャッシュしない素通し
実装（コメント参照）なので、この停滞はSWのキャッシュではなくOS/ブラウザ側の
ページ復元によるもの。

- `document.lastModified`（現在表示中のHTMLが読み込まれた時点の
  `Last-Modified`ヘッダー値）を起動時の基準値として保持する
  （[shor.html:1959-1961](../shor.html#L1959-L1961)）
- フォアグラウンド復帰のたび（`visibilitychange`が`visible`、または
  `pageshow`の`persisted`）、`checkForUpdate()`
  （[shor.html:1962-1976](../shor.html#L1962-L1976)）が無キャッシュの`HEAD`
  リクエストで自分自身の最新の`Last-Modified`を取得し、基準値より新しければ
  画面上部に固定表示のバナー`#update-banner`
  （[shor.html:669-676](../shor.html#L669-L676)）を出す
- タップで`location.reload()`するだけで、**自動リロードはしない**。投稿の
  長文入力中や現像の5秒長押し中に不意にリロードされて作業が消えることを
  避けるため
- オフライン等で`fetch`が失敗した場合は無視し、次回のフォアグラウンド復帰時に
  また試す

`.screen`とは無関係な常設要素で、`.modal`（重ね表示）よりさらに低い
`z-index:9`（`#devbar`と同じ層）に置いてある。
