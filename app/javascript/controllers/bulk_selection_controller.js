import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "all", "actions", "count"]

  connect() {
    this.update()
  }

  toggleAll(event) {
    this.selectableItems.forEach(item => { item.checked = event.currentTarget.checked })
    this.update()
  }

  update() {
    const items = this.selectableItems
    const selected = items.filter(item => item.checked).length
    this.actionsTargets.forEach(panel => { panel.hidden = selected === 0 })
    this.countTargets.forEach(counter => { counter.textContent = `${selected} selected` })
    this.allTargets.forEach(checkbox => {
      checkbox.checked = items.length > 0 && selected === items.length
      checkbox.indeterminate = selected > 0 && selected < items.length
    })
  }

  get selectableItems() {
    return this.itemTargets.filter(item => !item.disabled)
  }
}
