import { Turbo } from "@hotwired/turbo-rails"

let dismissCurrentDialog

function showDialog(message, { title = "Confirm action", label = "Continue", cancel = true, danger = false, trigger = document.activeElement } = {}) {
  // A second submission must get its own decision rather than share an approval.
  if (dismissCurrentDialog) return Promise.resolve(false)

  const dialog = document.getElementById("app-dialog")
  if (!dialog || typeof dialog.showModal !== "function") return Promise.resolve(false)

  const cancelButton = dialog.querySelector("[data-dialog-cancel]")
  const acceptButton = dialog.querySelector("[data-dialog-accept]")
  const firstButton = cancel ? cancelButton : acceptButton
  dialog.querySelector("#app-dialog-title").textContent = title
  dialog.querySelector("#app-dialog-message").textContent = message
  dialog.dataset.kind = danger ? "danger" : "primary"
  cancelButton.hidden = !cancel
  acceptButton.textContent = label

  return new Promise(resolve => {
    const finish = approved => {
      if (dismissCurrentDialog !== dismiss) return

      dismissCurrentDialog = undefined
      cancelButton.removeEventListener("click", dismiss)
      acceptButton.removeEventListener("click", accept)
      dialog.removeEventListener("cancel", cancelWithEscape)
      dialog.removeEventListener("keydown", containFocus)
      dialog.close()
      document.documentElement.classList.remove("app-dialog-open")
      if (trigger?.isConnected) trigger.focus({ preventScroll: true })
      resolve(approved)
    }
    const dismiss = () => finish(false)
    const accept = () => finish(true)
    const cancelWithEscape = event => {
      event.preventDefault()
      dismiss()
    }
    const containFocus = event => {
      if (event.key !== "Tab") return

      if (event.shiftKey && document.activeElement === firstButton) {
        event.preventDefault()
        acceptButton.focus()
      } else if (!event.shiftKey && document.activeElement === acceptButton) {
        event.preventDefault()
        firstButton.focus()
      }
    }

    dismissCurrentDialog = dismiss
    cancelButton.addEventListener("click", dismiss)
    acceptButton.addEventListener("click", accept)
    dialog.addEventListener("cancel", cancelWithEscape)
    dialog.addEventListener("keydown", containFocus)
    dialog.showModal()
    document.documentElement.classList.add("app-dialog-open")
    firstButton.focus()
  })
}

Turbo.config.forms.confirm = (message, _form, submitter) => showDialog(message, {
  label: submitter?.textContent.trim() || submitter?.value || "Continue",
  danger: submitter?.classList.contains("admin-btn-danger"),
  trigger: submitter || document.activeElement
})

document.addEventListener("app:alert", event => {
  if (typeof event.detail?.message !== "string") return

  showDialog(event.detail.message, { title: event.detail.title || "Notice", label: "OK", cancel: false })
})

for (const event of ["turbo:before-visit", "turbo:before-render", "turbo:before-cache"]) {
  document.addEventListener(event, () => dismissCurrentDialog?.())
}
window.addEventListener("pagehide", () => dismissCurrentDialog?.())
