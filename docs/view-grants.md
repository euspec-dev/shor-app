# 閲覧権（視聴枠)の仕様

`shor.html` の実装（クライアント側）と、`supabase_migration.sql` /
`supabase_migration_002_defer_reservation.sql` / `supabase_migration_005_appday_boundary.sql`
の `peek_drift` / `confirm_drift` RPC（サーバ側）から起こした、閲覧権まわりの仕様。

## 概要

閲覧者が1日に写真を「見る」ことができる回数には上限があり、次の2種類の枠の
合計で決まる。

| 枠 | 付与条件 | 上限 |
|---|---|---|
| 無料枠 | 何もしなくても毎日付与される | 1日1回 |
| 投稿枠（ボーナス） | その日に自分も1通「海に流す」と付与される | 1日+1回（何通投稿しても+1のまま） |

つまり、**その日1通も投稿していなければ1日1枚まで、投稿していれば1日2枚まで**
閲覧できる。

## クライアント側の実装（localStorage）

- `freeUsedToday()` / `useFreeGrant()` （[shor.html:930-931](../shor.html#L930-L931)）
  `localStorage` の `shor:viewFreeUsed` に「無料枠を使った日付（`appDayStr()`、
  後述）」を保存する。値が今日の`appDayStr()`と一致していれば「今日はもう
  無料枠を使った」と判定する。
- `postGrants()` / `addPostGrant()` / `consumePostGrant()`
  （[shor.html:933-946](../shor.html#L933-L946)）
  `localStorage` の `shor:postGrants` に `{date, count, granted}`
  （`date`は`appDayStr()`）を保存する。`addPostGrant()` は投稿成功時
  （[shor.html:1292](../shor.html#L1292)、`createPost` 成功直後）に呼ばれる
  が、その日すでに `granted:true` なら何もしない — **同じ日に何通投稿しても、
  投稿ボーナスは+1しか増えない。**
- `canView()` （[shor.html:947](../shor.html#L947)）
  `!freeUsedToday() || postGrants() > 0`。無料枠が未消費、または投稿枠の残数が
  あれば閲覧可能。ボタンを押せるかどうかの入り口の判定にのみ使う。
- `consumeView()` （[shor.html:948-951](../shor.html#L948-L951)）
  無料枠が未消費ならまず無料枠を消費し、消費済みなら投稿枠を1つ消費する。
  **無料枠が優先的に消費される。**

### 消費されるタイミング: 現像が完了した瞬間

`consumeView()` は「誰かの感性に触れる」を押した時点（＝画面を開いた時点）
ではなく、**現像インタラクションが完了した瞬間**に呼ばれる
（[shor.html:1106-1107](../shor.html#L1106-L1107)、`tick()` 内で
`developed` が `true` になる箇所）。

写真を開いただけで長押しをやめて離脱した場合は枠を消費しない。実際に
5秒間の長押し（現像）をやり切った時点で初めて「1枚見た」とみなす。

## サーバ側: peek（覗くだけ）と confirm（確定）の分離

サーバ側も、クライアントの枠消費と同じ瞬間に予約が確定するよう、
2つのRPCに分けてある。

1. **`peek_drift(viewer_id)`** （候補を選ぶだけ、副作用なし）
   写真を開いた瞬間 `getRandomDrift()`（[shor.html:1055](../shor.html#L1055)）
   から呼ばれる。加重ランダムで候補を選んで返すだけで、`view_count` の増分も
   `view_history` への記録も一切行わない。何度呼んでも状態は変わらない。
2. **`confirm_drift(viewer_id, post_id)`** （現像完了時に呼ぶ、ここで確定）
   `confirmDrift()`（[shor.html:815-820](../shor.html#L815-L820)）から、
   `tick()` 内で `developed` が `true` になった瞬間（[shor.html:1107](../shor.html#L1107)）
   に呼ばれる。ここで初めて:
   - 1日の視聴上限チェック（後述）
   - 対象投稿がまだ有効か（`peek` から時間が経っている間に上限到達/期限切れ/
     既視聴になっていないか）の再検証
   - `view_count` のアトミックな増分、`max_reach` 到達時の `exhausted` 遷移
   - `view_history` への予約行（`viewed_seconds=0`）の挿入

   を1つのUPDATE文＋INSERT文で行う。競合や期限切れで確定できなかった場合は
   `false` を返すが、稀なケースなのでクライアント側は黙って無視し、体験上は
   そのまま鑑賞を続けさせる（サーバ側の集計に反映されないだけ）。

confirmDrift() の呼び出しは非同期（fire-and-forget）だが、現像完了直後に
指を離した際に呼ばれる `recordViewHistoryDB()`（`viewed_seconds` の確定更新）
より先に `view_history` の予約行が挿入されている必要があるため、
`release()`（[shor.html:1140-1144](../shor.html#L1140-L1144)）は
`confirmDrift()` の完了を待ってから `recordViewHistoryDB()` を呼ぶよう
順序を保証している。UI側の画面遷移（washed演出など）はこの待ち合わせを
またずに即座に始まる。

### なぜ2段階に分けたか

以前は1つの `select_drift` RPCが「候補選択」と「予約」を同時に行っており、
クライアントの枠消費（`consumeView()`）は開いた瞬間に行っていた。この場合、
写真を開いただけで現像せずに離脱すると、クライアントの枠は減らないのに
サーバ側は既にその日の視聴回数としてカウント済み、という矛盾が起きていた
（例: 無料枠が残っていると表示されるのに、次に開こうとするとサーバ側の
上限判定に引っかかって「まだ写真が届いていません」という誤解を招く表示になる）。
peek/confirmに分離し、どちらも「現像完了」という同じ瞬間に合わせたことで
このズレを解消している。

### リセットのタイミング: 深夜0時ではなく朝7時

`appDayStr()` （[shor.html:759-762](../shor.html#L759-L762)）が「アプリ内の
1日」の文字列を作る。**現在時刻から7時間引いた時点の日付**をその日として
扱う実装（`APP_DAY_SHIFT_MS = 7 * 60 * 60 * 1000`）で、端末の**ローカル
時刻**基準。つまり無料枠・投稿枠のリセットは「ローカル時間の朝7時」を境に
起こり、深夜0時〜6時59分はまだ前日として扱われる。`appYesterdayStr()`
（[shor.html:763-767](../shor.html#L763-L767)）は同じ区切りでの前日を返す。

以前は`todayStr()`（深夜0時区切り）を使っていたが、「1日の区切りが深夜0時
だと、寝る前・寝起きの生活リズムと合わない」という理由で朝7時区切りに変更した。
`freeUsedToday`/`postGrants`系の関数（`appDayStr()`を直接使う）だけでなく、
`renderHome()`の前日結果判定（[shor.html:970](../shor.html#L970)）・
`getResultForDate()`の集計期間（[shor.html:873-893](../shor.html#L873-L893)、
後述）・devbar（`dev-yesterday`/`dev-skip`）まで、**日付境界に関わる箇所は
全て`appDayStr()`/`appYesterdayStr()`に統一**してある。

なお投稿の結果表示自体は、この後の機能追加で日付単位から投稿単位
（`shor:myPosts`、[data-model.md](data-model.md)参照）に変わっており、
`lastPostDate`は新規の投稿では書き込まれなくなった。`renderHome()`は
今も`lastPostDate`を読むが、これはこの変更より前からの保留結果を一度だけ
拾うための後方互換パスとしてのみ残っている（[screens.md](screens.md)の
「結果モーダル」節参照）。

## 上限に達したときのUI

`canView() === false` のとき、押した場所によって2箇所で分岐する
（どちらも同じ文言判定ロジック）。

- ホーム画面「誰かの感性に触れる」（[shor.html:1502-1514](../shor.html#L1502-L1514)）
- 投稿完了画面「誰かの感性に触れる」（[shor.html:1421-1427](../shor.html#L1421-L1427)）

その日すでに投稿済み（`postGrants` が `granted:true`）かどうかで文言が変わる。

| 状況 | 表示文言 |
|---|---|
| 投稿済みで両方使い切った | 「未開封のボトルメールは以上です。朝7時に、次の一通が流れ着きます。」 |
| 未投稿で無料枠を使い切った | 「ボトルメールは1日1通だけ届きます。自分のボトルメールを海に流すと、追加で1通だけ届きます。」 |

これはあくまで「ボタンを押せるか」の入り口の判定であり、実際に枠が減るのは
前述の通り現像完了時点である。

## サーバ側の視聴上限チェック（confirm_drift）

クライアントの制限はローカルストレージだけで担保されており、API を直接叩けば
バイパスできてしまう。そのため `confirm_drift(viewer_id, post_id)`
（`supabase_migration_002_defer_reservation.sql`で新設、
`supabase_migration_005_appday_boundary.sql`で日付境界を朝7時基準に修正）
でも同じ上限をサーバ側で再検証している。

- 当日の `view_history` 件数（＝実際に現像が完了して確定した閲覧数）を数える
- 当日、自分名義の投稿（`is_seed=false`）が存在するかを見て、投稿ボーナスの
  有無を判定する
- `許可数 = free_view_per_day(既定1) + (投稿していれば post_view_bonus 既定1)`
- 件数が許可数以上ならその場で `false` を返す（予約しない）

これらの既定値は `distribution_config` テーブルに切り出されており、
クライアントを一切変更せずにSQLで調整できる
（例: `update distribution_config set free_view_per_day = 2;`）。

### 「今日」の境界: サーバ側は日本時間の朝7時で判定する

`confirm_drift`内の`v_day_start`は、以前は`date_trunc('day', now())`
（**データベースのタイムゾーン、通常UTC基準の深夜0時**）だったが、
クライアントの`appDayStr()`（ローカル時刻基準の朝7時区切り）に合わせるため、
`supabase_migration_005_appday_boundary.sql`で次の式に変更した。

```sql
v_day_start := (
  date_trunc('day', (now() AT TIME ZONE 'Asia/Tokyo') - interval '7 hours')
  + interval '7 hours'
) AT TIME ZONE 'Asia/Tokyo';
```

`now()`を日本時間に変換してから7時間引いて日付に丸め、7時間戻す
（＝`appDayStr()`と同じ考え方をSQLで再現）ことで、「日本時間の朝7時」に
相当する`timestamptz`を求めている。

### 注意: クライアント端末のタイムゾーンがJSTでない場合はまだズレる

サーバ側は`'Asia/Tokyo'`に固定してある一方、クライアントの`appDayStr()`は
**端末のローカル時刻**を使う。想定ユーザーは日本在住・端末もJST設定という
前提のもとでは両者は一致するが、万一海外滞在中や端末のタイムゾーン設定が
JST以外になっている場合は、以前と同種の「クライアントとサーバで『今日』の
認識がズレる」問題が再発しうる。現状は実害が出るほど厳密な運用ではないため
未対応だが、認識しておくべき前提。

## まとめ: 1日に見られる枚数

- 投稿していない日: **最大1枚**（無料枠のみ）
- 投稿した日: **最大2枚**（無料枠1 + 投稿ボーナス1。複数投稿しても2枚のまま）
- どちらも「現像をやり切った」時点で1枚消費とカウントする
