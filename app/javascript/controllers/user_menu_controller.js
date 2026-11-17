import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "form", "status", "avatar"]
  static values = { theme: String, density: String }

  connect() {
    this.close()
    this.apply({ theme: this.themeValue, ui_density: this.densityValue })
    if (this.hasAvatarTarget && this.avatarTarget.complete && this.avatarTarget.naturalWidth === 0) this.avatarError()
    this.systemTheme = window.matchMedia("(prefers-color-scheme: dark)")
    this.systemChanged = () => this.notifyAppearance()
    this.systemTheme.addEventListener("change", this.systemChanged)
  }

  disconnect() {
    this.systemTheme?.removeEventListener("change", this.systemChanged)
  }

  toggle() {
    this.triggerTarget.setAttribute("aria-expanded", String(this.element.open))
  }

  close() {
    this.element.open = false
    this.toggle()
  }

  dismiss(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  escape(event) {
    if (!this.element.open) return
    event.preventDefault()
    this.close()
    this.triggerTarget.focus()
  }

  avatarError() {
    this.avatarTarget.hidden = true
  }

  async save() {
    if (this.saving) return
    const form = this.formTarget
    const theme = form.elements.namedItem("preferences[theme]")
    const density = form.elements.namedItem("preferences[ui_density]")
    const previous = { theme: this.themeValue, ui_density: this.densityValue }
    const preferences = { theme: theme.value, ui_density: density.value }
    const controls = [...form.querySelectorAll('input[type="radio"]')]
    const focused = document.activeElement
    this.saving = true
    controls.forEach(control => { control.disabled = true })
    this.statusTarget.textContent = "Saving…"
    this.apply(preferences)

    try {
      const response = await fetch(form.action, {
        method: "PATCH", credentials: "same-origin", keepalive: true,
        headers: { "Accept": "application/json", "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body: JSON.stringify({ preferences })
      })
      const saved = await response.json()
      if (!response.ok || !["system", "light", "dark"].includes(saved.theme) || !["normal", "condensed"].includes(saved.ui_density)) {
        throw new Error("Preferences could not be saved")
      }
      this.themeValue = saved.theme
      this.densityValue = saved.ui_density
      if (!this.element.isConnected) return
      theme.value = saved.theme
      density.value = saved.ui_density
      this.apply(saved)
      this.statusTarget.textContent = "Saved"
    } catch (_error) {
      if (!this.element.isConnected) return
      theme.value = previous.theme
      density.value = previous.ui_density
      this.apply(previous)
      this.statusTarget.textContent = "Couldn’t save your preferences. Please try again."
    } finally {
      this.saving = false
      controls.forEach(control => { control.disabled = false })
      if (this.element.isConnected && this.element.open && document.activeElement === document.body && controls.includes(focused)) {
        focused.focus({ preventScroll: true })
      }
    }
  }

  apply(preferences) {
    document.documentElement.dataset.theme = preferences.theme
    document.documentElement.dataset.density = preferences.ui_density
    this.notifyAppearance()
  }

  notifyAppearance() {
    document.dispatchEvent(new CustomEvent("appearance:change"))
  }
}
