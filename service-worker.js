/* PWAのインストール条件を満たすための最小限のService Worker。
   オフラインキャッシュ等は行わず、リクエストをそのまま素通しする。 */
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", (e) => {
  e.respondWith(fetch(e.request));
});
