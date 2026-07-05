/*
 * config.js のひな形。
 * 使い方: このファイルをコピーして同じ場所に "config.js" という名前で保存し、
 * 値を埋めてください（config.js は .gitignore 対象で、GitHubには上がりません）。
 *
 *   cp config.example.js config.js
 *
 * SUPABASE_URL / SUPABASE_ANON_KEY は Supabase ダッシュボード →
 * Project Settings → API から確認できます。
 *
 * IS_DEV: true にすると開発用バー（リセット/前日投稿/一日進める）と
 * EXIF検証スキップが有効になる。本番では必ず false にすること
 * （このひな形の既定値も false なので、コピーしただけでは有効にならない）。
 */
window.SHOR_CONFIG = {
  SUPABASE_URL: "",
  SUPABASE_ANON_KEY: "",
  IS_DEV: false
};
