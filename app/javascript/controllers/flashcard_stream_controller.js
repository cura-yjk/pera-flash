import { Controller } from "@hotwired/stimulus"

// Generates flashcards with each card appearing as soon as it is written,
// rather than all of them at once after the last.
//
// Sits on the "Generate flashcards" form and sends it itself, with fetch
// rather than EventSource. EventSource can only GET, and it reconnects on its
// own after an error -- which here would quietly spend another generation.
// A POST keeps the form's CSRF token and the controller's rate limits exactly
// as they were.
//
// Whatever is not a stream -- nothing new to card, rate limited -- comes back
// as an ordinary turbo_stream and goes to Turbo, as it did before.
export default class extends Controller {
  static values = { failed: String }

  async generate(event) {
    event.preventDefault()
    if (this.busy) return

    this.busy = true
    this.button?.setAttribute("disabled", "")

    try {
      const response = await fetch(this.element.action, {
        method: "POST",
        body: new FormData(this.element),
        headers: { Accept: "text/event-stream, text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })

      if (response.headers.get("Content-Type")?.startsWith("text/event-stream")) {
        await this.read(response)
      } else {
        window.Turbo.renderStreamMessage(await response.text())
      }
    } catch {
      this.fail()
    } finally {
      this.busy = false
      this.button?.removeAttribute("disabled")
    }
  }

  get button() {
    return this.element.querySelector("button, [type=submit]")
  }

  get preview() {
    return document.getElementById("flashcard-preview")
  }

  // Server-sent events arrive as "event: name\ndata: json" frames separated by
  // a blank line, split across reads wherever the network likes.
  async read(response) {
    const reader = response.body.pipeThrough(new TextDecoderStream()).getReader()
    let buffer = ""
    this.ended = false

    for (;;) {
      const { value, done } = await reader.read()
      if (done) break

      buffer += value
      let boundary
      while ((boundary = buffer.indexOf("\n\n")) >= 0) {
        this.handle(buffer.slice(0, boundary))
        buffer = buffer.slice(boundary + 2)
      }
    }

    // The connection closed without saying how it went.
    if (!this.ended) this.fail()
  }

  handle(frame) {
    const name = frame.match(/^event: (.*)$/m)?.[1]
    const data = JSON.parse(frame.match(/^data: (.*)$/m)?.[1] || "{}")

    switch (name) {
      case "open":
        this.preview.innerHTML = data.html
        break
      case "card":
        this.preview.querySelector("[data-flashcard-list]")?.insertAdjacentHTML("beforeend", data.html)
        break
      case "reset":
        this.preview.querySelector("[data-flashcard-list]")?.replaceChildren()
        break
      case "done":
        this.ended = true
        this.preview.querySelector("[data-flashcard-status]")?.remove()
        this.preview.querySelector("[data-flashcard-save]")?.removeAttribute("disabled")
        break
      case "failed":
        this.ended = true
        this.preview.innerHTML = data.html
        break
    }
  }

  // Nothing was saved, so the notice only has to say try again. Its text comes
  // from the page, rendered through the same translation as the server's.
  fail() {
    this.ended = true
    this.preview.innerHTML = this.failedValue
  }
}
