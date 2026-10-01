import { Controller } from "@hotwired/stimulus"
import DOMPurify from "dompurify"
import { marked } from "marked"

const markdownTags = [
  "a", "blockquote", "br", "code", "del", "em", "h1", "h2", "h3", "h4", "h5", "h6", "hr",
  "li", "ol", "p", "pre", "strong", "table", "tbody", "td", "th", "thead", "tr", "ul"
]

export default class extends Controller {
  static targets = ["messages", "form", "input", "submit", "submitLabel", "error", "context", "contextToken", "contextStatus"]
  static values = { autostart: Boolean }

  static streamInterruptedMessage = "The answer stream was interrupted before it finished. The response may have been too large or the connection may have timed out. Please try again, or ask a narrower question."

  connect() {
    this.history = []
    this.verifiedSources = []
    this.copyFeedbackTimeouts = new WeakMap()
    this.debugPanelSequence = this.messagesTarget.querySelectorAll(".chat-debug-panel").length
    this.autostart()
  }

  autostart() {
    if (!this.autostartValue || document.documentElement.hasAttribute("data-turbo-preview")) return

    // Turbo can restore this page from its cache. Clear the flag before submitting so the
    // restored page does not send the same question again.
    this.autostartValue = false
    if (this.inputTarget.value.trim()) this.formTarget.requestSubmit()
  }

  // The signed search context travels with every turn, because the transcript is held in the
  // browser and the server has no conversation to attach it to.
  contextParams() {
    const token = this.hasContextTokenTarget ? this.contextTokenTarget.value : ""
    return token ? { context_token: token } : {}
  }

  removeContext() {
    if (this.hasContextTokenTarget) this.contextTokenTarget.value = ""
    if (this.hasContextTarget) this.contextTarget.remove()
    if (this.hasContextStatusTarget) {
      this.contextStatusTarget.textContent = "Search context removed. Answers now cover the whole collection."
    }
    this.inputTarget.focus()
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

    const assistant = this.appendMessage("Collections Assistant", "", "assistant")
    const assistantContent = assistant.querySelector(".chat-message-content")
    const placeholder = this.buildPlaceholder()
    const status = placeholder.querySelector(".chat-status")
    assistantContent.append(placeholder)
    let responseText = ""
    let toolCallCount = 0

    try {
      const response = await fetch(this.formTarget.action, {
        method: "POST",
        headers: {
          "Accept": "text/event-stream",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({ messages: this.history, ...this.contextParams() })
      })

      if (!response.ok) {
        const data = await response.json().catch(() => ({}))
        throw new Error(data.error || "The chat request could not be started.")
      }
      if (!response.body) throw new Error("Streaming is not supported by this browser.")

      await this.consumeStream(response.body, (type, data) => {
        if (type === "delta") {
          placeholder.remove()
          responseText += data.content
          this.renderAssistant(assistantContent, responseText, this.verifiedSources, placeholder)
        } else if (type === "reset") {
          responseText = ""
          this.renderAssistant(assistantContent, responseText, this.verifiedSources, placeholder)
        } else if (type === "status") {
          status.textContent = data.message
          if (!placeholder.isConnected) assistantContent.append(placeholder)
        } else if (type === "sources") {
          this.verifiedSources = this.mergeVerifiedSources(data.sources)
          this.renderAssistant(assistantContent, responseText, this.verifiedSources, placeholder)
        } else if (type === "notice") {
          this.appendNotice(assistant, data.message)
        } else if (type === "tool_call") {
          toolCallCount += 1
          status.textContent = "Synthesizing…"
          if (!placeholder.isConnected) assistantContent.append(placeholder)
          this.appendToolCall(assistant, data, toolCallCount)
        } else if (type === "error") {
          throw new Error(data.message)
        }
      })

      if (!responseText) throw new Error("The chat service did not return an answer. Please try again.")
      placeholder.remove()
      this.renderMarkdown(assistantContent, responseText, this.verifiedSources)
      this.appendCopyButton(assistant, assistantContent, responseText)
      this.history.push({ role: "assistant", content: responseText })
    } catch (error) {
      assistant.remove()
      userMessage.remove()
      this.history.pop()
      this.showError(error.message)
      this.inputTarget.value = content
    } finally {
      this.setBusy(false)
    }
  }

  async consumeStream(body, callback) {
    const reader = body.getReader()
    const decoder = new TextDecoder()
    let buffer = ""
    let eventName = "message"
    let dataLines = []
    let completed = false

    const processLine = (line) => {
      if (line === "") {
        if (dataLines.length > 0) {
          if (eventName === "done") completed = true
          callback(eventName, JSON.parse(dataLines.join("\n")))
        }
        eventName = "message"
        dataLines = []
      } else if (line.startsWith("event:")) {
        eventName = line.slice(6).trim()
      } else if (line.startsWith("data:")) {
        dataLines.push(line.slice(5).trimStart())
      }
    }

    try {
      while (true) {
        const { value, done } = await reader.read()
        buffer += decoder.decode(value || new Uint8Array(), { stream: !done })
        const lines = buffer.split(/\r?\n/)
        buffer = lines.pop()
        lines.forEach(processLine)
        if (done) break
      }
    } catch (error) {
      console.error("Chat response stream interrupted:", error)
      throw new Error(this.constructor.streamInterruptedMessage)
    }
    if (buffer) processLine(buffer)
    processLine("")
    if (!completed) {
      console.error("Chat response stream ended before the done event was received")
      throw new Error(this.constructor.streamInterruptedMessage)
    }
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
    return article
  }

  // One node, so re-appending it after a render preserves the caption's current text.
  buildPlaceholder() {
    const placeholder = document.createElement("div")
    placeholder.className = "chat-placeholder"

    const skeleton = document.createElement("div")
    skeleton.className = "skeleton chat-skeleton placeholder-glow"
    skeleton.setAttribute("aria-hidden", "true")
    for (const width of ["col-12", "col-10", "col-7"]) {
      const bar = document.createElement("span")
      bar.className = `placeholder ${width}`
      skeleton.append(bar)
    }

    const status = document.createElement("div")
    status.className = "chat-status text-body-secondary mt-2"
    status.textContent = "Thinking…"

    placeholder.append(skeleton, status)
    return placeholder
  }

  // renderMarkdown empties the bubble, so the placeholder goes back whenever there is no text.
  renderAssistant(container, text, sources, placeholder) {
    this.renderMarkdown(container, text, sources)
    if (!text) container.append(placeholder)
  }

  appendNotice(message, content) {
    const notice = document.createElement("div")
    notice.className = "chat-source-notice alert alert-warning mt-2 mb-0"
    notice.textContent = content
    message.append(notice)
    return notice
  }

  appendToolCall(message, call, count) {
    let debug = message.querySelector(".chat-debug")
    if (!debug) {
      debug = document.createElement("div")
      debug.className = "chat-debug mt-2"

      const button = document.createElement("button")
      button.type = "button"
      button.className = "btn btn-sm btn-outline-secondary chat-debug-toggle"
      button.setAttribute("aria-expanded", "false")
      button.textContent = "Show tool calls (0)"

      const panel = document.createElement("div")
      panel.className = "chat-debug-panel mt-2"
      panel.hidden = true
      panel.id = `chat-debug-${++this.debugPanelSequence}`
      button.setAttribute("aria-controls", panel.id)
      button.addEventListener("click", () => {
        panel.hidden = !panel.hidden
        button.setAttribute("aria-expanded", String(!panel.hidden))
        button.textContent = `${panel.hidden ? "Show" : "Hide"} tool calls (${panel.childElementCount})`
      })

      debug.append(button, panel)
      message.append(debug)
    }

    const entry = document.createElement("section")
    entry.className = "chat-debug-entry"
    const heading = document.createElement("div")
    heading.className = "chat-debug-heading"
    heading.textContent = `${count}. ${call.name || "Unknown tool"}`
    entry.append(heading)

    for (const [label, value] of [["Arguments", call.arguments], ["Result", call.result]]) {
      const title = document.createElement("div")
      title.className = "chat-debug-label"
      title.textContent = label
      const body = document.createElement("pre")
      body.textContent = this.formatToolValue(value)
      entry.append(title, body)
    }

    const panel = debug.querySelector(".chat-debug-panel")
    panel.append(entry)
    const button = debug.querySelector(".chat-debug-toggle")
    button.textContent = `${panel.hidden ? "Show" : "Hide"} tool calls (${count})`
  }

  formatToolValue(value) {
    if (typeof value !== "string") return JSON.stringify(value ?? {}, null, 2)
    try {
      return JSON.stringify(JSON.parse(value), null, 2)
    } catch {
      return value
    }
  }

  appendCopyButton(message, content, markdown) {
    const actions = document.createElement("div")
    actions.className = "chat-message-actions mt-2"

    const button = document.createElement("button")
    button.type = "button"
    button.className = "chat-copy btn btn-sm btn-link"
    button.setAttribute("aria-label", "Copy response")
    button.title = "Copy response"

    const icon = document.createElement("i")
    icon.className = "bi bi-clipboard"
    icon.setAttribute("aria-hidden", "true")
    button.append(icon)

    const feedback = document.createElement("span")
    feedback.className = "chat-copy-feedback"
    feedback.setAttribute("role", "status")

    button.addEventListener("click", () => this.copyResponse(icon, feedback, content, markdown))

    actions.append(button, feedback)
    message.append(actions)
    return actions
  }

  async copyResponse(icon, feedback, content, markdown) {
    try {
      await this.writeToClipboard(this.formattedHtml(content), markdown)
      this.showCopyFeedback(icon, feedback, "bi-check2", "Copied")
    } catch (error) {
      console.error("Copying the chat response failed:", error)
      this.showCopyFeedback(icon, feedback, "bi-exclamation-triangle", "Copy failed")
    }
  }

  // Writes both the formatted and plain text flavors so pasting into a rich text
  // editor keeps the formatting and pasting into a plain text field keeps the markdown.
  async writeToClipboard(html, markdown) {
    if (!navigator.clipboard?.write || typeof ClipboardItem === "undefined") {
      return navigator.clipboard.writeText(markdown)
    }

    return navigator.clipboard.write([
      new ClipboardItem({
        "text/html": new Blob([html], { type: "text/html" }),
        "text/plain": new Blob([markdown], { type: "text/plain" })
      })
    ])
  }

  // Citation links are relative to this site, so they need to be absolute to survive the paste.
  formattedHtml(content) {
    const copy = content.cloneNode(true)
    copy.querySelectorAll("a[href]").forEach((link) => {
      try {
        link.setAttribute("href", new URL(link.getAttribute("href"), document.baseURI).toString())
      } catch {
        link.removeAttribute("href")
      }
    })
    return copy.innerHTML
  }

  showCopyFeedback(icon, feedback, iconClass, message) {
    clearTimeout(this.copyFeedbackTimeouts.get(icon))
    icon.className = `bi ${iconClass}`
    feedback.textContent = message
    this.copyFeedbackTimeouts.set(icon, setTimeout(() => {
      icon.className = "bi bi-clipboard"
      feedback.textContent = ""
    }, 3000))
  }

  renderMarkdown(container, text, sources) {
    const sourcesByUrl = new Map(sources.map((source) => [source.url, source]))
    const html = marked.parse(text, { breaks: true, gfm: true })
    const sanitizedHtml = DOMPurify.sanitize(html, {
      ALLOWED_TAGS: markdownTags,
      ALLOWED_ATTR: ["href"]
    })
    const template = document.createElement("template")
    template.innerHTML = sanitizedHtml

    template.content.querySelectorAll("a").forEach((link) => {
      const href = link.getAttribute("href")
      const source = sourcesByUrl.get(href)
      if (source) {
        link.setAttribute("href", this.citationUrl(source, link.textContent))
        return
      }

      link.replaceWith(document.createTextNode(link.textContent))
    })

    this.linkSourceReferences(template.content, sources)
    container.replaceChildren(template.content)
  }

  mergeVerifiedSources(sources) {
    const sourcesByUrl = new Map(this.verifiedSources.map((source) => [source.url, source]))

    if (!Array.isArray(sources)) return Array.from(sourcesByUrl.values())

    sources.forEach((source) => {
      if (!source?.title || !source?.url) return

      sourcesByUrl.set(source.url, { ...sourcesByUrl.get(source.url), ...source })
    })

    return Array.from(sourcesByUrl.values())
  }

  linkSourceReferences(fragment, sources) {
    const sourcesByTitle = new Map(
      sources
        .filter((source) => source.title && this.safeSourceUrl(source.url))
        .map((source) => [source.title, source])
    )
    const titles = Array.from(sourcesByTitle.keys()).sort((a, b) => b.length - a.length)
    if (titles.length === 0) return

    const titlePattern = new RegExp(
      `(${titles.map(this.escapeRegExp).join("|")})(,\\s+pp?\\.\\s+\\d+(?:\\s*(?:[-–—]|,\\s*)\\s*\\d+)*)?`,
      "g"
    )
    const walker = document.createTreeWalker(fragment, NodeFilter.SHOW_TEXT)
    const textNodes = []

    while (walker.nextNode()) {
      const textNode = walker.currentNode
      if (!textNode.parentElement?.closest("a, code, pre")) textNodes.push(textNode)
    }

    textNodes.forEach((textNode) => {
      const matches = Array.from(textNode.data.matchAll(titlePattern))
      if (matches.length === 0) return

      const replacement = document.createDocumentFragment()
      let previousIndex = 0
      matches.forEach((match) => {
        replacement.append(document.createTextNode(textNode.data.slice(previousIndex, match.index)))
        const link = document.createElement("a")
        const source = sourcesByTitle.get(match[1])
        link.href = this.citationUrl(source, match[0])
        link.textContent = match[0]
        replacement.append(link)
        previousIndex = match.index + match[0].length
      })
      replacement.append(document.createTextNode(textNode.data.slice(previousIndex)))
      textNode.replaceWith(replacement)
    })
  }

  citationUrl(source, citationText) {
    const page = citationText.match(/,\s+pp?\.\s+(\d+)/)?.[1]
    const verifiedPages = Array.isArray(source.pages) ? source.pages.map(String) : []
    if (!page || !verifiedPages.includes(page)) return source.url

    const url = new URL(source.url, document.baseURI)
    url.searchParams.set("canvas_index", Number.parseInt(page, 10) - 1)
    return url.toString()
  }

  escapeRegExp(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  }

  safeSourceUrl(url) {
    try {
      return ["http:", "https:"].includes(new URL(url, document.baseURI).protocol)
    } catch {
      return false
    }
  }

  setBusy(busy) {
    const label = busy ? "Searching…" : "Send"
    this.submitTarget.disabled = busy
    this.inputTarget.disabled = busy
    this.submitTarget.setAttribute("aria-label", label)
    this.submitLabelTarget.textContent = label
    this.messagesTarget.setAttribute("aria-busy", busy.toString())
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
