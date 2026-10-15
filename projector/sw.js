// Migration from the old projector-only cache. No page reloads or data changes.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => {
  event.waitUntil(caches.delete('raiseroster-projector-shell-v1').then(() => self.registration.unregister()));
});
