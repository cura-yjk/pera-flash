// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "@popperjs/core"
import "bootstrap"

// Registers the service worker that makes the app installable. Failure is not
// worth surfacing: the site works exactly the same without it, and browsers
// that refuse it (private windows, unsupported versions) would otherwise log
// an error on every page.
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker").catch(() => {})
  })
}
