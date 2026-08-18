import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dark-toggle"];

  connect () {
  const savedTheme = localStorage.getItem("theme");

  if (savedTheme === "dark") {
    document.body.classList.add("dark-mode");
    }
  }


  toggle() {
    document.body.classList.toggle("dark-mode");

    if (this.hasDarkToggleTarget) {
      this.darkToggleTarget.classList.toggle("dark-btn");
    }

    const isDark = document.body.classList.contains("dark-mode");
    localStorage.setItem("theme", isDark ? "dark" : "light");
  }
}
