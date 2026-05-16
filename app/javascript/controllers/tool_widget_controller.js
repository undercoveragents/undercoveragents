import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["phrase"]

  static values = {
    completeMessages: Array,
    initialPhrase: String,
    runningIntervalMs: Number,
    runningMessages: Array,
    runningMode: String,
    status: String,
  }

  connect() {
    this.rotationTimer = null
    this.fadeTimer = null
    this.lastPhrase = null
    this.completePhrase = null
    this.rotationQueue = []
    this.syncState()
  }

  disconnect() {
    this.stopRotation()
    if (this.fadeTimer) window.clearTimeout(this.fadeTimer)
  }

  statusValueChanged() {
    this.syncState()
  }

  runningMessagesValueChanged() {
    this.rotationQueue = []
    if (this.isRunning()) this.syncState()
  }

  completeMessagesValueChanged() {
    if (!this.isRunning()) this.syncState()
  }

  runningModeValueChanged() {
    if (this.isRunning()) this.syncState()
  }

  runningIntervalMsValueChanged() {
    if (this.isRunning()) this.syncState()
  }

  syncState() {
    this.stopRotation()
    this.element.classList.toggle("streaming", this.isRunning())

    if (this.isRunning()) {
      this.completePhrase = null
      this.showPhrase(this.initialPhraseValue || this.pickRunningPhrase())
      this.initialPhraseValue = ""
      this.startRotation()
    } else {
      this.completePhrase ||= this.initialPhraseValue || this.pickCompletePhrase()
      this.showPhrase(this.completePhrase)
      this.initialPhraseValue = ""
    }
  }

  startRotation() {
    if (this.runningModeValue !== "rotate") return
    if (this.runningMessagesValue.length < 2) return

    this.rotationTimer = window.setInterval(() => {
      this.showPhrase(this.nextRotatingPhrase())
    }, this.runningIntervalMsValue)
  }

  stopRotation() {
    if (!this.rotationTimer) return

    window.clearInterval(this.rotationTimer)
    this.rotationTimer = null
  }

  showPhrase(text) {
    if (!this.hasPhraseTarget) return

    const nextText = text || ""
    if (!this.phraseTarget.textContent.trim()) {
      this.phraseTarget.textContent = nextText
      this.lastPhrase = nextText
      return
    }

    if (this.phraseTarget.textContent.trim() === nextText) return

    this.phraseTarget.classList.add("is-fading")
    if (this.fadeTimer) window.clearTimeout(this.fadeTimer)

    this.fadeTimer = window.setTimeout(() => {
      this.phraseTarget.textContent = nextText
      this.phraseTarget.classList.remove("is-fading")
      this.lastPhrase = nextText
    }, 140)
  }

  pickRunningPhrase() {
    return this.sampleMessage(this.runningMessagesValue)
  }

  pickCompletePhrase() {
    return this.sampleMessage(this.completeMessagesValue)
  }

  nextRotatingPhrase() {
    const messages = this.runningMessagesValue.filter(Boolean)
    if (messages.length <= 1) return messages[0] || ""

    if (this.rotationQueue.length === 0) {
      const seed = [...messages]
      this.shuffle(seed)
      if (seed[0] === this.lastPhrase && seed.length > 1) {
        const first = seed.shift()
        seed.push(first)
      }
      this.rotationQueue = seed
    }

    return this.rotationQueue.shift() || ""
  }

  sampleMessage(messages) {
    const available = messages.filter(Boolean)
    if (available.length === 0) return ""
    if (available.length === 1) return available[0]

    const alternatives = available.filter((message) => message !== this.lastPhrase)
    const pool = alternatives.length > 0 ? alternatives : available
    return pool[Math.floor(Math.random() * pool.length)]
  }

  shuffle(values) {
    for (let index = values.length - 1; index > 0; index -= 1) {
      const swapIndex = Math.floor(Math.random() * (index + 1))
      ;[values[index], values[swapIndex]] = [values[swapIndex], values[index]]
    }
  }

  isRunning() {
    return this.statusValue === "running"
  }
}
