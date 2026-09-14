import { Controller } from "@hotwired/stimulus"

// Hides a card's answer until the learner has attempted to recall it, then
// swaps the "show answer" prompt for the grade buttons.
export default class extends Controller {
  static targets = ["answer", "prompt", "grades"]

  show() {
    this.answerTarget.hidden = false
    this.promptTarget.hidden = true
    this.gradesTarget.hidden = false
  }
}
