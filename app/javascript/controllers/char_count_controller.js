import { Controller } from "@hotwired/stimulus"

// Shows how much room is left, but only near the limit.
//
// The field carries maxlength, so at 2,000 characters the browser simply stops
// accepting keystrokes with no explanation. A counter that is always on screen
// is noise; one that appears when it starts to matter is a warning.
const WARN_WITHIN = 120

export default class extends Controller {
  static targets = ["input", "counter"]
  static values = { limit: Number, template: String }

  connect() {
    this.update()
  }

  update() {
    const remaining = this.limitValue - this.inputTarget.value.length

    this.counterTarget.hidden = remaining > WARN_WITHIN
    this.counterTarget.textContent = this.templateValue.replace("%{count}", remaining)
  }
}
