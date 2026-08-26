import { Controller } from "@hotwired/stimulus"
import DOMPurify from "dompurify"
import { marked } from "marked"

const markdownTags = [
  "a", "blockquote", "br", "code", "del", "em", "h1", "h2", "h3", "h4", "h5", "h6", "hr",
  "li", "ol", "p", "pre", "strong", "table", "tbody", "td", "th", "thead", "tr", "ul"
]

export default class extends Controller {
  static targets = ["messages", "form", "input", "submit", "error"]

  connect() {
    this.history = []
  }

  keydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.formTarget.requestSubmit()
    }
  }

  async submit(event) {
    event.preventDefault()
    const content = this.inputTarget.value.trim()
    if (!content || this.submitTarget.disabled) return

    this.hideError()
    const userMessage = this.appendMessage("You", content, "user")
    this.history.push({ role: "user", content })
    this.inputTarget.value = ""
    this.setBusy(true)

    const assistant = this.appendMessage("Collections assistant", "", "assistant")
    const assistantContent = assistant.querySelector(".chat-message-content")
    const status = this.appendStatus(assistant)
    let responseText = ""
    let verifiedSources = []

    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST",
        headers: {
          "Accept": "text/event-stream",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({ messages: this.history })
      })

      if (!response.ok) {
        const data = await response.json().catch(() => ({}))
        throw new Error(data.error || "The chat request could not be started.")
      }
      if (!response.body) throw new Error("Streaming is not supported by this browser.")

      await this.consumeStream(response.body, (type, data) => {
        if (type === "delta") {
          status.remove()
          responseText += data.content
          this.renderMarkdown(assistantContent, responseText, verifiedSources)
        } else if (type === "reset") {
          responseText = ""
          assistantContent.textContent = ""
        } else if (type === "status") {
          status.textContent = data.message
          if (!status.isConnected) assistant.append(status)
        } else if (type === "sources") {
          verifiedSources = data.sources
          this.renderMarkdown(assistantContent, responseText, verifiedSources)
          this.appendSources(assistant, verifiedSources)
        } else if (type === "error") {
          throw new Error(data.message)
        }
        this.scrollToLatest()
      })

      if (!responseText) responseText = "I couldn’t produce an answer from the available corpus."
      status.remove()
      this.renderMarkdown(assistantContent, responseText, verifiedSources)
      this.history.push({ role: "assistant", content: responseText })
    } catch (error) {
      assistant.remove()
      userMessage.remove()
      this.history.pop()
      this.showError(error.message)
      this.inputTarget.value = content
    } finally {
      this.setBusy(false)
      this.inputTarget.focus()
    }
  }

  async consumeStream(body, callback) {
    const reader = body.getReader()
    const decoder = new TextDecoder()
    let buffer = ""
    let eventName = "message"
    let dataLines = []

    const processLine = (line) => {
      if (line === "") {
        if (dataLines.length > 0) callback(eventName, JSON.parse(dataLines.join("\n")))
        eventName = "message"
        dataLines = []
      } else if (line.startsWith("event:")) {
        eventName = line.slice(6).trim()
      } else if (line.startsWith("data:")) {
        dataLines.push(line.slice(5).trimStart())
      }
    }

    while (true) {
      const { value, done } = await reader.read()
      buffer += decoder.decode(value || new Uint8Array(), { stream: !done })
      const lines = buffer.split(/\r?\n/)
      buffer = lines.pop()
      lines.forEach(processLine)
      if (done) break
    }
    if (buffer) processLine(buffer)
    processLine("")
  }

  appendMessage(label, content, role) {
    const article = document.createElement("article")
    article.className = `chat-message chat-message-${role}`

    const messageLabel = document.createElement("div")
    messageLabel.className = "chat-message-label"
    messageLabel.textContent = label

    const messageContent = document.createElement("div")
    messageContent.className = "chat-message-content"
    messageContent.textContent = content

    article.append(messageLabel, messageContent)
    this.messagesTarget.append(article)
    this.scrollToLatest()
    return article
  }

  appendStatus(message) {
    const status = document.createElement("div")
    status.className = "chat-status mt-2"
    status.textContent = "Thinking…"
    message.append(status)
    return status
  }

  appendSources(message, sources) {
    if (!Array.isArray(sources) || sources.length === 0) return

    const title = document.createElement("div")
    title.className = "chat-sources-title"
    title.textContent = "Sources"
    const list = document.createElement("ul")
    list.className = "chat-sources"
    sources.forEach((source) => {
      const item = document.createElement("li")
      const link = document.createElement("a")
      link.href = source.url
      link.textContent = source.title
      item.append(link)
      list.append(item)
    })
    message.append(title, list)
  }

  renderMarkdown(container, text, sources) {
    const allowedUrls = new Set(sources.map((source) => source.url))
    const html = marked.parse(text, { breaks: true, gfm: true })
    const sanitizedHtml = DOMPurify.sanitize(html, {
      ALLOWED_TAGS: markdownTags,
      ALLOWED_ATTR: ["href"]
    })
    const template = document.createElement("template")
    template.innerHTML = sanitizedHtml

    template.content.querySelectorAll("a").forEach((link) => {
      const href = link.getAttribute("href")
      if (allowedUrls.has(href)) return

      link.replaceWith(document.createTextNode(link.textContent))
    })

    container.replaceChildren(template.content)
  }

  setBusy(busy) {
    this.submitTarget.disabled = busy
    this.inputTarget.disabled = busy
    this.submitTarget.value = busy ? "Searching…" : "Send"
    this.messagesTarget.setAttribute("aria-busy", busy.toString())
  }

  scrollToLatest() {
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("d-none")
  }

  hideError() {
    this.errorTarget.classList.add("d-none")
    this.errorTarget.textContent = ""
  }
}
