import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  open(event) {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    if (event.target.closest("a, button, input, select, textarea, label, summary, [contenteditable], [role='button'], [role='link'], [data-row-link-ignore]")) return
    if (window.getSelection()?.toString()) return

    this.linkTarget.click()
  }
}
