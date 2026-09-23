import { Controller } from "@hotwired/stimulus"

// Remembers the theme and puts it on <body>. Everything else is CSS.
//
// This used to walk .js-dash-card and stamp .dash-card-dark on each element at
// connect and on toggle, which only ever covered what was on the page at that
// moment. Anything Turbo delivered afterwards -- the edit modal in its frame,
// the rate-limit and reply-failed notices in their streams -- arrived
// unthemed, and toggling did not help, because toggling walked the same stale
// set. The stylesheet now matches on .dark-mode descendants, so a panel is
// themed the moment it exists.
export default class extends Controller {
  static targets = ["darkToggle"]

  connect() {
    if (localStorage.getItem("theme") === "dark") this.apply(true)
  }

  toggle() {
    this.apply(!document.body.classList.contains("dark-mode"))
    localStorage.setItem("theme", this.dark ? "dark" : "light")
  }

  apply(dark) {
    document.body.classList.toggle("dark-mode", dark)

    // The toggle button is its own control rather than a themed surface, and
    // it is always on the page, so it keeps its class.
    if (this.hasDarkToggleTarget) this.darkToggleTarget.classList.toggle("dark-btn", dark)
  }

  get dark() {
    return document.body.classList.contains("dark-mode")
  }
}
