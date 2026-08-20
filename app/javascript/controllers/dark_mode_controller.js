import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dark-toggle", "dark-dash",'rotate-icon'];

  connect () {
  const savedTheme = localStorage.getItem("theme");
  const dashCard = document.querySelectorAll(".js-dash-card");

  if (savedTheme === "dark") {
    document.body.classList.add("dark-mode");

    dashCard.forEach((card) => {
      card.classList.add("dash-card-dark");
    });

    if (this.hasDarkToggleTarget) {
      this.darkToggleTarget.classList.add("dark-btn");
    }
    if (this.hasDarkDashTarget) {
      this.darkDashTarget.classList.add("dash-card-dark");
    }
    }
  }

  toggle() {
    const dashCard = document.querySelectorAll(".js-dash-card");
    document.body.classList.toggle("dark-mode");

    dashCard.forEach((card) => {
      card.classList.toggle("dash-card-dark");
    });

    if (this.hasDarkToggleTarget) {
      this.darkToggleTarget.classList.toggle("dark-btn");
    }

    if (this.hasDarkDashTarget) {
      this.darkDashTarget.classList.toggle("dash-card-dark");
    }

    const isDark = document.body.classList.contains("dark-mode");
    localStorage.setItem("theme", isDark ? "dark" : "light");
  }
}
