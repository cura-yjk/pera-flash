// app/javascript/controllers/enter_submit_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit(event) {
    // Don't hijack Enter while an IME composition is in progress
    if (event.isComposing || event.keyCode === 229) return

    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()

      if (this.element.value.trim().length === 0) return

      this.element.closest("form").requestSubmit()
    }
  }
}
