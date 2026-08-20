import { Controller } from "@hotwired/stimulus";

export default class extends Controller {

  static targets = ["icon"];

  connect() {
    console.log("connected!");
  }

  start(event) {
    this.iconTarget.classList.remove("hidden");
  }
}
