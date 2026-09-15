import { Controller } from "@hotwired/stimulus"

// Grows the chat box with what is being written.
//
// It was two rows tall and fixed, so anything longer than a sentence was
// edited through a letterbox -- worst on a phone, where 62px of a small screen
// is already a lot to give to an input you cannot read.
//
// Stops growing at MAX_HEIGHT and scrolls after that, so a long paste cannot
// push the conversation off the screen.
const MAX_HEIGHT = 200

export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.resize()
  }

  resize() {
    const input = this.inputTarget

    // Collapse first: scrollHeight only shrinks back if the element is not
    // already holding itself open at the taller size.
    input.style.height = "auto"
    input.style.height = `${Math.min(input.scrollHeight, MAX_HEIGHT)}px`
    input.style.overflowY = input.scrollHeight > MAX_HEIGHT ? "auto" : "hidden"
  }
}
