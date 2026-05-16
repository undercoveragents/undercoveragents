import { fileIcon, truncateFilename } from "controllers/chat/dom_helpers"

export class PendingAttachments {
  constructor(chat) {
    this.chat = chat
  }

  add(files) {
    for (const file of files) {
      if (this.chat.pendingFiles.length >= this.chat.maxFiles) break
      if (file.size > this.chat.maxFileSize) continue
      if (!this.chat.attachmentAllowed(file)) continue
      this.chat.pendingFiles.push(file)
    }

    this.render()
    this.chat.inputBehavior.focusInput()
  }

  clear() {
    this.revokeObjectURLs()
    this.chat.pendingFiles = []
    this.render()
  }

  revokeObjectURLs() {
    if (!this.chat.hasAttachmentPreviewTarget) return

    this.chat.attachmentPreviewTarget
      .querySelectorAll(".shared-chat__attachment-card-image")
      .forEach((img) => URL.revokeObjectURL(img.src))
  }

  render() {
    if (!this.chat.hasAttachmentPreviewTarget) return

    const container = this.chat.attachmentPreviewTarget
    this.revokeObjectURLs()
    container.innerHTML = ""

    if (this.chat.pendingFiles.length === 0) {
      container.classList.add("hidden")
      return
    }

    container.classList.remove("hidden")
    this.chat.scrollToBottom()

    this.chat.pendingFiles.forEach((file, index) => {
      const card = document.createElement("div")
      card.className = "shared-chat__attachment-card"

      if (file.type.startsWith("image/")) {
        const img = document.createElement("img")
        img.src = URL.createObjectURL(file)
        img.className = "shared-chat__attachment-card-image"
        img.alt = file.name
        card.appendChild(img)
      } else {
        const icon = document.createElement("div")
        icon.className = "shared-chat__attachment-card-icon"
        icon.innerHTML = `<i class="fa-solid ${fileIcon(file)}"></i>`
        card.appendChild(icon)
      }

      const name = document.createElement("span")
      name.className = "shared-chat__attachment-card-name"
      name.textContent = truncateFilename(file.name, 20)
      name.title = file.name
      card.appendChild(name)

      const removeBtn = document.createElement("button")
      removeBtn.className = "shared-chat__attachment-card-remove"
      removeBtn.innerHTML = '<i class="fa-solid fa-xmark"></i>'
      removeBtn.type = "button"
      removeBtn.addEventListener("click", () => this.remove(index))
      card.appendChild(removeBtn)

      container.appendChild(card)
    })
  }

  remove(index) {
    this.chat.pendingFiles.splice(index, 1)
    this.render()
  }
}
