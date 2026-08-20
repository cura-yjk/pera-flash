// app/javascript/controllers/enter_submit_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "form"]

  connect() {
    this.composing = false
    this.handleCompositionStart = () => { this.composing = true }
    this.handleCompositionEnd = () => { this.composing = false }

    this.inputTarget.addEventListener("compositionstart", this.handleCompositionStart)
    this.inputTarget.addEventListener("compositionend", this.handleCompositionEnd)
  }

  disconnect() {
    this.inputTarget.removeEventListener("compositionstart", this.handleCompositionStart)
    this.inputTarget.removeEventListener("compositionend", this.handleCompositionEnd)
  }

  submit(event) {
    if (event.key !== "Enter" || event.shiftKey) return
    if (this.composing) return

    event.preventDefault()

    if (this.inputTarget.value.trim().length === 0) return

    this.formTarget.requestSubmit()
  }
}
