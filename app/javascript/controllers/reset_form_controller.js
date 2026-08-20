import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="reset-form"
export default class extends Controller {
  static targets = ["input", "submit"];

  // Triggered on form submit
  submit() {

    // 1. Instantly clear input field
    // Note: We use setTimeout to allow the form submission data to payload before clearing
    setTimeout(() => {
      this.inputTarget.value = ""
    }, 0)

    // 2. Disable submit button to prevent double clicks
    this.submitTarget.disabled = true

    this.submitTarget.innerText = '<i class="fa-solid fa-spinner fa-spin-pulse hidden" id="load-icon" data-load-target="icon"></i>';
  }
}
