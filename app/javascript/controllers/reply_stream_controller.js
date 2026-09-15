import { Controller } from "@hotwired/stimulus"

// Streams Pera's reply into the page as it is generated.
//
// While tokens arrive they are shown as plain text: markdown cannot be
// rendered from a half-finished string -- a table is nonsense until its last
// row lands, and a furigana annotation is literal brackets until its closing
// one arrives. The finished message is rendered server-side and swapped in
// whole at the end, so what the student keeps is the properly formatted
// version with its readings.
export default class extends Controller {
  static targets = ["text", "cursor"]
  static values = { url: String }

  connect() {
    this.source = new EventSource(this.urlValue)

    this.source.addEventListener("token", (event) => this.append(event))
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
    const { text } = JSON.parse(event.data)

    this.textTarget.textContent += text
    this.scrollIntoView()
  }

  finish(event) {
    const { html, title } = JSON.parse(event.data)

    this.close()
    this.element.outerHTML = html
    this.updateTitle(title)
    this.scrollIntoView()
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

  scrollIntoView() {
    this.element.scrollIntoView({ behavior: "smooth", block: "end" })
  }
}
