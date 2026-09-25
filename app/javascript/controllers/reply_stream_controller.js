import { Controller } from "@hotwired/stimulus"

// How far behind the model the reveal is allowed to run, in seconds. The model
// sends a sentence or more at a time; showing each lump as it lands made the
// reply lurch forward in steps. Letting the text out at the rate of the
// backlog over this long keeps it flowing, and speeds up when the model does.
const CATCH_UP_SECONDS = 0.8

// Characters per second when the backlog is nearly gone. Without a floor the
// last few words of every lump crawl out as the rate above decays to nothing.
const MIN_SPEED = 40

// The newest text fades in over roughly this many characters -- a word or
// three -- so it arrives rather than blinks on.
const FADE_CHARACTERS = 20
const FADE_STEP = 4

// Streams Pera's reply into the page as it is generated.
//
// Each update arrives already rendered -- markdown, tables and furigana -- so
// what streams in looks like what is kept, rather than raw asterisks and
// pipes being rewritten at the end. The server does that rendering, which
// keeps one markdown path and one sanitizer rather than a second
// implementation in the browser that could disagree with it. What this does
// with it is choose how much of it to show.
export default class extends Controller {
  static targets = ["text", "cursor"]
  static values = { url: String }

  connect() {
    // Nothing stopped a second message being sent while the first was still
    // being answered. It saved fine, but the reply endpoint only answers the
    // last unanswered question, so the second one sat there looking ignored.
    this.lockInput()
    this.makeRoom()

    this.reply = document.createElement("div")
    this.shown = 0
    this.total = 0
    this.instant = window.matchMedia("(prefers-reduced-motion: reduce)").matches

    this.source = new EventSource(this.urlValue)

    this.source.addEventListener("chunk", (event) => this.append(event))
    this.source.addEventListener("done", (event) => this.finish(event))
    this.source.addEventListener("failed", () => this.fail())
    // Fires when the connection drops rather than closing cleanly. A reply
    // that was already swapped in has nothing left to fail.
    this.source.onerror = () => { if (this.source) this.fail() }
  }

  disconnect() {
    this.close()
    this.stopRevealing()
    this.unlockInput()
  }

  // The form is replaced wholesale by each turbo_stream response, so this
  // looks it up rather than holding a reference to an element that may already
  // have been thrown away.
  lockInput(locked = true) {
    document.querySelectorAll("#new_message textarea, #new_message button[type=submit]")
            .forEach((field) => { field.disabled = locked })
  }

  unlockInput() {
    this.lockInput(false)
  }

  // Brings the question just sent up under the navbar, and holds the rest of
  // the window open beneath it for the reply to grow into.
  //
  // The page used to follow the reply down as it arrived, which kept the text
  // being written pinned against the input box and moved the page under the
  // reader every time a chunk landed. Now it moves once, when you send, and
  // then holds still: the reply fills the space below your question and you
  // scroll on when you are ready.
  //
  // The space is a min-height rather than padding so that a reply longer than
  // the window simply outgrows it. It stays after the reply finishes -- taking
  // it away then would pull the page down under the reader -- and is handed
  // back when the next question is sent.
  makeRoom() {
    document.querySelectorAll("[data-reply-room]").forEach((earlier) => {
      earlier.style.minHeight = ""
      earlier.removeAttribute("data-reply-room")
    })

    const question = this.element.previousElementSibling
    if (!question) return

    const gap = parseFloat(getComputedStyle(question).scrollMarginTop) || 0
    const target = question.getBoundingClientRect().top + window.scrollY - gap

    // Measured rather than worked out from the layout: the bubble's margins
    // collapse differently once it has a min-height, and predicting that came
    // out 32px short. The second pass picks up whatever the first one moved.
    for (let pass = 0; pass < 2; pass++) {
      const shortfall = target - (document.documentElement.scrollHeight - window.innerHeight)
      if (shortfall <= 0) break

      this.element.style.minHeight = `${this.element.offsetHeight + Math.ceil(shortfall)}px`
    }

    this.element.setAttribute("data-reply-room", "")
    question.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  append(event) {
    const { html } = JSON.parse(event.data)
    const before = this.reply.textContent

    this.reply.innerHTML = html
    this.total = this.reply.textContent.length

    // A retry on the next API key starts the reply again from the beginning.
    // Keep whatever of the new text matches what is already on screen, and
    // reveal from where the two part.
    this.shown = Math.min(this.shown, sharedPrefixLength(before, this.reply.textContent))

    this.reveal()
  }

  finish(event) {
    this.close()
    this.finished = JSON.parse(event.data)

    // Waits for the reveal to catch up, so the finished message is not a jump
    // to the end of text that was still flowing in.
    this.reveal()
  }

  fail() {
    this.close()
    this.stopRevealing()
    this.show(this.total)
    this.unlockInput()
    this.cursorTarget.innerHTML =
      '<i class="fa-solid fa-triangle-exclamation text-warning"></i> ' +
      "Pera couldn't reply just now. Your message is saved — try sending it again."
  }

  reveal() {
    if (this.instant) this.shown = this.total
    if (this.frame) return

    this.frame = requestAnimationFrame((now) => this.step(now))
  }

  // Time is measured between frame timestamps only. Measuring from
  // performance.now() at the moment a frame was requested went negative, as a
  // frame's timestamp can be from before the request -- the count went below
  // zero, the excerpt threw, and the reply stopped on an empty bubble. After a
  // pause (caught up, waiting on the model) the first frame counts as no time
  // at all, so the next lump does not spill out in one go.
  step(now) {
    this.frame = null

    const seconds = this.lastFrame == null ? 0 : Math.max(0, (now - this.lastFrame) / 1000)
    this.lastFrame = now

    const backlog = this.total - this.shown
    const speed = Math.max(backlog / CATCH_UP_SECONDS, MIN_SPEED)
    const before = Math.floor(this.shown)

    this.shown = Math.min(this.total, this.shown + speed * seconds)
    if (Math.floor(this.shown) !== before || this.instant) this.show(this.shown)

    if (this.shown < this.total) {
      this.reveal()
    } else {
      this.lastFrame = null
      if (this.finished) this.complete()
    }
  }

  stopRevealing() {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
  }

  show(characters) {
    this.textTarget.replaceChildren(...excerpt(this.reply, Math.floor(characters)).childNodes)
  }

  // Swaps in the finished message, rendered by the same partial as a page
  // load. It goes inside this element rather than in place of it, because this
  // element is what holds the room made for the reply.
  complete() {
    const { html, title } = this.finished

    this.element.innerHTML = html
    this.element.removeAttribute("data-controller")
    this.unlockInput()
    this.updateTitle(title)
  }

  // The first exchange names the conversation, and the heading was rendered
  // before that happened.
  updateTitle(title) {
    if (!title) return

    const heading = document.querySelector("#conversation_title h1, #conversation_title h2")
    if (heading) heading.textContent = title
  }

  close() {
    this.source?.close()
    this.source = null
  }
}

// The first `count` characters of the rendered reply, still inside the markup
// they belong to -- a bold word stays bold and a table grows cell by cell --
// with the newest few fading in.
function excerpt(source, count) {
  const copy = source.cloneNode(true)
  const walker = document.createTreeWalker(copy, NodeFilter.SHOW_TEXT)
  const kept = []
  let remaining = count
  let node

  while ((node = walker.nextNode())) {
    kept.push(node)

    if (node.length >= remaining) {
      if (node.length > remaining) node.splitText(remaining)
      removeEverythingAfter(node, copy)
      break
    }

    remaining -= node.length
  }

  fadeIn(kept)
  return copy
}

function removeEverythingAfter(node, root) {
  for (let current = node; current !== root; current = current.parentNode) {
    while (current.nextSibling) current.nextSibling.remove()
  }
}

// Wraps the last FADE_CHARACTERS of text in spans that get fainter towards
// the end. Rebuilt every frame, so as the end moves on, text brightens.
// Whitespace between tags is skipped: a span dropped between two table rows
// would itself be laid out as a cell.
function fadeIn(textNodes) {
  let fromEnd = 0

  for (const node of textNodes.reverse()) {
    if (fromEnd >= FADE_CHARACTERS) break
    if (!node.data.trim()) continue

    while (fromEnd < FADE_CHARACTERS && node.length > 0) {
      const take = Math.min(FADE_STEP, FADE_CHARACTERS - fromEnd, node.length)
      const piece = node.splitText(node.length - take)
      const span = document.createElement("span")

      span.style.opacity = (0.15 + 0.85 * (fromEnd + take / 2) / FADE_CHARACTERS).toFixed(2)
      piece.replaceWith(span)
      span.append(piece)
      fromEnd += take
    }
  }
}

function sharedPrefixLength(a, b) {
  let length = 0
  while (length < a.length && a[length] === b[length]) length++
  return length
}
