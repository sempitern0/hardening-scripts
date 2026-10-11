/* Audit Workbench service worker: immutable local shell only. No audit data is cached. */
'use strict';
const CACHE_NAME = 'audit-workbench-shell-v6';
const CORE = [
  './', './index.html', './styles.css', './app.js',
  './normalize.css', './manifest.webmanifest', './icons/dragon.svg', './icons/icon-192.png', './icons/icon-512.png'
];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(CORE)));
});
self.addEventListener('activate', event => {
  event.waitUntil(Promise.all([
    caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('audit-workbench-shell-') && key !== CACHE_NAME).map(key => caches.delete(key)))),
    self.clients.claim()
  ]));
});
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin || !url.pathname.startsWith(new URL(self.registration.scope).pathname)) return;
  event.respondWith(caches.match(request).then(cached => cached || fetch(request)));
});
