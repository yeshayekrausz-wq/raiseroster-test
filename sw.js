// Increment VERSION whenever releasing changes to cached files.
const VERSION = '1.12.0';
const CACHE = 'ykonnect-launcher-' + VERSION;
const BASE = new URL('./', self.location.href);
const SHELL = ['index.html', 'shared/hub.css', 'shared/hub.js', 'shared/programs.js', 'shared/config.js', 'shared/membership.js', 'install.js', 'manifest.webmanifest', 'favicon2.png', 'icons/icon-192.png', 'icons/icon-512.png', 'offline.html'].map(path => new URL(path, BASE).href);
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)));
  // Do not skipWaiting: never replace an active editing session.
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('ykonnect-launcher-') && key !== CACHE).map(key => caches.delete(key)))));
  // Do not claim existing pages or force a reload.
});
// Rebuild followed redirects before using them for a navigation response.
// Static hosts redirect index.html to / and offline.html to /offline.
function navigationSafe(response) {
  if (!response) return new Response('Offline. Please reconnect and reload.', {status: 503, headers: {'Content-Type': 'text/plain; charset=utf-8'}});
  if (!response.redirected) return response;
  return new Response(response.body, {status: response.status, statusText: response.statusText, headers: response.headers});
}
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== BASE.origin) return;
  const home = url.pathname === BASE.pathname || url.pathname === new URL('index.html', BASE).pathname;
  if (request.mode === 'navigate' && !home) {
    event.respondWith(fetch(request).catch(() => caches.match(new URL('offline.html', BASE).href).then(navigationSafe)));
    return;
  }
  const key = home ? new URL('index.html', BASE).href : url.href;
  if (SHELL.includes(key)) event.respondWith(caches.match(key).then(cached => cached ? navigationSafe(cached) : fetch(request)));
  // Never cache API responses, student data, authenticated pages or mutations.
});
