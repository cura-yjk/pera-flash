import { Controller } from "@hotwired/stimulus"

// How far from the bottom of the page still counts as "reading along". Roughly
// a message's height: far enough that the reply arriving does not feel jumpy,
// close enough that scrolling up to re-read something stops the page chasing
// the text back down.
const FOLLOW_THRESHOLD = 400

// Streams Pera's reply into the page as it is generated.
//
// Each update arrives already rendered -- markdown, tables and furigana -- so
// what streams in looks like what is kept, rather than raw asterisks and
// pipes being rewritten at the end. The server does that rendering, which
// keeps one markdown path and one sanitizer rather than a second
// implementation in the browser that could disagree with it.
export default class extends Controller {
  static targets = ["text", "cursor"]
  static values = { url: String }

  connect() {
    this.source = new EventSource(this.urlValue)

    this.source.addEventListener("chunk", (event) => this.append(event))
    this.source.addEventListener("done", (event) => this.finish(event))
    this.source.addEventListener("failed", () => this.fail())
    // Fires when the connection drops rather than closing cleanly. A reply
    // that was already swapped in has nothing left to fail.
    this.source.onerror = () => { if (this.source) this.fail() }
  }

  disconnect() {
    this.close()
  }

  append(event) {
    const { html } = JSON.parse(event.data)

    this.textTarget.innerHTML = html
    this.scrollToLatest()
  }

  finish(event) {
    const { html, title } = JSON.parse(event.data)

    this.close()
    this.element.outerHTML = html
    this.updateTitle(title)
    this.scrollToLatest()
  }

  fail() {
    this.close()
    this.cursorTarget.innerHTML =
      '<i class="fa-solid fa-triangle-exclamation text-warning"></i> ' +
      "Pera couldn't reply just now. Your message is saved — try sending it again."
  }

  // The first exchange names the conversation, and the heading was rendered
  // before that happened.
  updateTitle(title) {
    if (!title) return

    const heading = document.querySelector("#conversation_title h1, #conversation_title h2")
    if (heading) heading.textContent = title
  }

  close() {
    this.source?.close()
    this.source = null
  }

  // Follows the reply as it arrives, but only while the reader is already at
  // the bottom. Scrolling unconditionally on every chunk drags the page back
  // down each time someone scrolls up to re-read an earlier answer.
  //
  // block: "end" lines the reply's bottom up with the bottom of the window,
  // which the input box covers. Measured, that left the newest text 100px
  // underneath it; .chat-page sets scroll-margin-bottom so the browser leaves
  // the dock room, which turns that into 44px of clearance.
  scrollToLatest() {
    if (!this.followingAlong()) return

    this.element.scrollIntoView({ behavior: "smooth", block: "end" })
  }

  followingAlong() {
    const fromBottom = document.documentElement.scrollHeight - window.scrollY - window.innerHeight

    return fromBottom < FOLLOW_THRESHOLD
  }
}
