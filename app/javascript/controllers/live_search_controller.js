import { Controller } from "@hotwired/stimulus"

// Searches as you type, rather than making you finish and press a button.
//
// Waits for a pause in typing before asking the server: a query per keystroke
// would send five requests for "ねこが" and show four sets of results nobody
// asked for on the way to the one they did.
const PAUSE_MS = 250

export default class extends Controller {
  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), PAUSE_MS)
  }

  // A pending search after the page has moved on would replace a frame that is
  // no longer there.
  disconnect() {
    clearTimeout(this.timeout)
  }
}
