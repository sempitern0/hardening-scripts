/* Audit Workbench service worker: immutable local shell only. No audit data is cached. */
'use strict';
const CACHE_NAME = 'audit-workbench-shell-v29-input-guidance';
const OPTIONAL_FONTS = ['Regular','Bold','Italic','BoldItalic'].map(weight => `./fonts/AtkinsonHyperlegible-${weight}.woff2`);
const CORE = [
  './', './index.html', './css/styles.css', './js/app.js', './js/audit-storage.js',
  './css/normalize.css', './css/team.css', './css/contrast.css', './css/relations.css', './js/audit-relations.js', './css/templates.css', './css/quality.css', './js/audit-quality.js', './css/retest.css', './js/audit-retest.js', './css/comparison.css', './js/audit-comparison.js', './js/control-templates.js', './css/print.css', './js/exporters.js', './js/hardware-catalog.js', './js/os-catalog.js', './js/glossary.js', './js/inventory-import.js', './js/input-guidance.js', './css/glossary.css', './css/atkinson.css', './manifest.webmanifest', './icons/os-windows.svg', './icons/os-linux.svg', './icons/os-macos.svg', './icons/dragon.svg', './icons/icon-192.png', './icons/icon-512.png'
];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(async cache => {
    await cache.addAll(CORE);
    await Promise.all(OPTIONAL_FONTS.map(path => cache.add(path).catch(() => undefined)));
  }));
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
  // Explicit connectivity probes must reach the origin, never the offline shell cache.
  if (request.cache === 'no-store') {
    event.respondWith(fetch(request));
    return;
  }
  event.respondWith(caches.match(request).then(async cached => {
    if (cached) return cached;
    const response = await fetch(request);
    // Cache only self-hosted font assets after a successful request. Optional
    // fonts must not prevent a ZIP distribution without WOFF2 from installing.
    if (response.ok && url.pathname.endsWith('.woff2') && url.pathname.includes('/fonts/')) {
      event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.put(request, response.clone())));
    }
    return response;
  }));
});
