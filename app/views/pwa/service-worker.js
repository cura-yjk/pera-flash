// Minimal by design.
//
// Chrome will not offer to install a site without a service worker that
// handles fetch, so this exists mostly to make the app installable. It does
// not cache pages: every screen here is server-rendered from data that changes
// as you study, and a cached dashboard showing yesterday's due count would be
// worse than no dashboard.
//
// What it does do is answer a navigation attempted with no connection, so the
// app opens to an explanation rather than the browser's dinosaur.

const OFFLINE_URL = "/offline.html"
const CACHE = "pera-offline-v1"

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.add(OFFLINE_URL)))
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  // Drop caches from older versions of this worker rather than letting them
  // accumulate in the user's storage quota forever.
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(
      keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))
    )).then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", (event) => {
  // GET navigations only.
  //
  // Handling every navigation meant form submissions went through here too,
  // and passing a POST Request back to fetch() intermittently lost it: a
  // quiz answer or a settings toggle would click through to nothing, once in
  // every few attempts. Nothing about a POST benefits from an offline page
  // anyway -- there is no cached answer to a form.
  if (event.request.method !== "GET") return
  if (event.request.mode !== "navigate") return

  event.respondWith(
    fetch(event.request).catch(() => caches.match(OFFLINE_URL))
  )
})
