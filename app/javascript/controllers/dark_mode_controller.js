import { Controller } from "@hotwired/stimulus"

const toggleBtn = document.querySelector(".js-toggle-btn");
const darkBtn = document.querySelector(".js-dark-btn");
const savedTheme = localStorage.getItem("theme");

if (savedTheme === "dark") {
  document.body.classList.add("dark-mode");
}

toggleBtn.addEventListener("click", () => {
  document.body.classList.toggle("dark-mode");
  darkBtn.classList.toggle("dark-btn");

  const isDark = document.body.classList.contains("dark-mode");
  localStorage.setItem("theme", isDark ? "dark" : "light");
});
