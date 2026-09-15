import { Controller } from "@hotwired/stimulus"

// Records whether the answer is on screen, so a round trip can put the card
// back the way it was.
//
// Lives on the form rather than in reveal_controller because the readings
// toggle sits outside the card it describes, and a Stimulus target only
// reaches inside its own controller's element.
export default class extends Controller {
  capture() {
    const answer = document.querySelector("[data-reveal-target='answer']")
    const field = this.element.querySelector("input[name='revealed']")

    if (!answer || !field) return

    field.value = answer.hidden ? "" : "1"
  }
}
