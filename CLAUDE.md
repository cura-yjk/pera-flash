# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

Pera Flash is a Rails 8 app for learning Japanese by talking. A learner chats with ペラ (Pera), an
LLM tutor that corrects their Japanese and explains the grammar, and any conversation can be turned
into flashcards. Those cards are organised into decks, reviewed on a spaced-repetition schedule,
quizzed as multiple choice, searched, and exported as Anki-importable CSV. The app installs as a
PWA.

## Commands

- Setup: `bin/setup` (installs gems, prepares the DB; `--skip-server` skips starting the server)
- Run dev server: `bin/dev`
- Run all tests: `bin/rails test` (does **not** include system tests)
- Run system tests: `bin/rails test:system` (real browser; kept separate, as in `config/ci.rb`).
  Chrome by default and in CI; `BROWSER=firefox bin/rails test:system` runs the same suite in Firefox
- Run a single test file: `bin/rails test test/models/flashcard_test.rb`
- Run a single test: `bin/rails test test/models/flashcard_test.rb -n test_method_name`
- Lint: `bin/rubocop` (`rubocop-rails-omakase` base)
- Security scan: `bin/brakeman`
- Gem vulnerability audit: `bin/bundler-audit`
- Full CI pipeline: `bin/ci` — setup, rubocop, bundler-audit, `bin/importmap audit`, brakeman,
  `bin/rails test`, then `db:seed:replant` in `RAILS_ENV=test` as a smoke test of `db/seeds.rb`.
  See `config/ci.rb`. GitHub Actions (`.github/workflows/ci.yml`) runs the same checks split into a
  lint/security job and a test job against a Postgres service container.

Requires `GEMINI_API_KEYS` for anything that talks to Pera — see **LLM usage** below for why it is
plural. Nothing else needs a key: review, quiz and export are all local.

## Architecture

**Domain model**: `User` -> has many `Conversation`s and `Deck`s. A `Conversation` has many
`Message`s (`role` enum: system/user/assistant) and many `Flashcard`s. A `Deck` has many
`Flashcard`s. A `Flashcard` `belongs_to` both `conversation` and `deck` **optionally** — a card can
come from a chat, be filed in a deck, or both — so there is no `user_id` on it and ownership is
resolved through `Flashcard.for_user`, which left-joins both parents and matches either one's
`user_id`. Use that scope rather than reaching for a direct user association that doesn't exist.

A `Conversation` is named after the first thing the learner says (`Conversation#name_after`, called
from `MessagesController#create`), and can be renamed in place from its title — `edit`/`update`,
inside the `conversation_title` turbo frame. Naming is deliberately **not** an LLM call: the
model-written titles cost a free-tier request per chat, held up the first reply, fell back to
"Let's chat!" whenever Gemini was busy, and were often worse than the message itself.

Two classes in `app/models/` are **not** ActiveRecord:

- `QuizQuestion` — one multiple-choice question, built per request. `OPTION_COUNT` is 4 and the
  distractors are sampled from the learner's own other cards rather than generated, which keeps a
  quiz free and offline and makes wrong answers plausibly confusable. There is no `quiz_questions`
  table.
- `Page` — a hand-rolled paginator (`Page.of(scope, number)`, `DEFAULT_SIZE` 24). There is no
  Kaminari or Pagy; don't add one without replacing this.

**LLM usage (`LlmChat` -> `PeraPrompt` -> `PeraReply`)**: `LlmChat`
(`app/services/llm_chat.rb`) is the single place that names a model — `gemini-3.5-flash` on
`:gemini`, with thinking explicitly disabled (`thinkingBudget: 0`; the comment there records the
measured latency difference). Everything calls `LlmChat.with_chat { |chat| ... }`, never
`RubyLLM.chat` directly, so changing model or provider is a one-file change.

Credentials come from **`GEMINI_API_KEYS`** — a comma-separated list. Quota is per key, so
`with_chat` catches `RubyLLM::RateLimitError` and re-yields a fresh chat on the next key; any other
error is raised immediately. This is why the block must do the *whole* exchange rather than just
build the chat: a retry has to replay the instructions and history. Singular `GEMINI_API_KEY` is
read as a fallback. The `openai_api_key` line in `config/initializers/ruby_llm.rb` is a spare
credential for a provider the app is **not** pointed at — don't infer the provider from it.

**No automatic retries** (`config.max_retries = 0` in the same initializer): one tap or message is
one request. ruby_llm's default retried timeouts, 5xx and 429s three more times, so a single tap on
a bad Gemini day spent four of the free tier's few daily requests and took two minutes to report a
timeout. Failures show a notice asking the learner to try again. Moving to the next key is not a
retry and still happens. Note Google applies free-tier limits per *project*, so keys created in the
same project share one allowance and rotating between them gains nothing.

`PeraPrompt` holds everything Pera is told before a conversation starts, including `FURIGANA_RULE`,
which is deliberately **shared** between the chat and the flashcard generator so a word taught in
chat and the card made from it are annotated identically. `PeraReply` decides what the model sees:
`MAX_HISTORY_MESSAGES` (30) bounds the replayed history — every reply used to replay everything, so
a chat's cost grew with the square of its length — and `STRUGGLING_LIMIT` (5) injects the cards the
learner keeps failing, which is the app's durable memory in place of unbounded history.

**Streaming replies**: `MessagesController` includes `ActionController::Live`. The exchange is two
requests: `#create` saves what the learner wrote and hands back an empty bubble, then `#stream`
sends the reply as server-sent events, consumed by `reply_stream_controller.js`. The stream sets
`X-Accel-Buffering: no` (without it the proxy buffers and the reply arrives as one lump). Note the
`ensure` sits inside the action around the streaming only, not around the record lookup — wrapping
the lookup meant a 404 committed a 200 on its way out. Each event carries the whole reply-so-far,
not a delta, so a mid-exchange key retry redraws instead of doubling the text. The browser does not
show each event as it lands: it reveals the rendered HTML a few characters per frame, at a speed
set by the backlog, with the newest characters fading in, and swaps in the finished message only
once the reveal catches up. Sending scrolls the question up under the navbar once and holds a
`min-height` below it for the reply; the page does not follow the reply down.

**Generating flashcards (`FlashcardGeneration`)**: the prompt, the request and the limits live in
`app/services/flashcard_generation.rb`; `ConversationsController#generate_flashcards` only renders.
Input is `Conversation#messages_for_flashcards` — what was said since the last batch, capped at
`FLASHCARD_MESSAGE_LIMIT` (20) — and output is capped at `FlashcardsSchema::MAX_CARDS` (10), set in
the schema, the prompt and a trim. Every generation logs one `Flashcard generation for
conversation …` line with its time and input size. The action streams when the browser sends
`Accept: text/event-stream` (`flashcard_stream_controller.js` does, POSTing with `fetch` — not
`EventSource`, which can only GET and reconnects on its own, spending another generation):
`StreamedCards` picks each card out of the JSON as it completes and it is sent as rendered HTML.
Everything short of a generation is still a turbo_stream, handed to Turbo. `EventStreaming`
(`app/controllers/concerns/`) holds the SSE helpers both controllers share.

Duplicates are caught by lookup, not by asking the model: `KnownCards` indexes the learner's cards by
their text with readings, spacing, punctuation and 〜 removed, against both question *and* answer
(cards from before fronts became Japanese carry the Japanese on the back). A generated card that
repeats one — or an earlier card in the batch — is marked in the preview, and the save checks again
(the learner may have edited it) and skips it. "Since the last batch" keys off
`conversations.carded_at`, stamped by `mark_carded!` *after* the "✅ N cards added" message, so an
all-duplicate save still ends the batch and the confirmation is never new material; conversations
carded before the column existed fall back to their newest card.

**Spaced repetition (`Flashcard`)**: an SM-2 variant, all local. `GRADES` are `again`/`good`/`easy`;
`review!(grade)` updates `interval_days`, `ease` (`STARTING_EASE` 2.5, floor `MINIMUM_EASE` 1.3) and
`due_at`. Two judgements are expressed in constants and worth preserving: `struggling` keys off
`lapse_count >= STRUGGLING_LAPSES` (2) rather than ease, because a lapse is something that actually
happened while ease also drifts for cards answered "easy" a lot; and `mastered?` requires
`interval_days >= MASTERED_INTERVAL_DAYS` (7) **and** fewer than two lapses. Review order comes from
the `due` and `in_review_order` scopes — never studied first, then most overdue.

**Deck export (`DecksController#export`)**: CSV, Anki-importable. Three details are deliberate and
easy to "fix" wrongly: the `Question,Answer` headers are what Anki maps fields by, so they are
pinned by a test and must not be renamed to anything friendlier; the response is prefixed with a
UTF-8 BOM so spreadsheet apps read Japanese correctly; and `spreadsheet_safe` prefixes any value
starting with a formula trigger to defuse CSV injection. **This feature belongs to a teammate —
document it, don't rewrite it.**

**Auth and scoping**: Devise on `User` (`database_authenticatable, registerable, recoverable,
rememberable, validatable, lockable` — `lockable` means repeated failed sign-ins lock an
account); `ApplicationController` applies `authenticate_user!` to
every action, so public controllers must explicitly `skip_before_action`. Extra registration fields
go through `configure_permitted_parameters`, not a Devise override. **Every lookup is scoped through
`current_user`** (`current_user.conversations.find(...)`, `Flashcard.for_user(current_user)`) —
preserve that when adding actions. `ConversationsController` also uses Rails 8's built-in
`rate_limit` on generation, per user, burst and hourly.

**Interface language**: English only. The app shipped six interface languages and a per-user
locale; that was removed deliberately to cut the cost of every new string being copy for six files.
Copy still goes through `t()` and `config/locales/en.yml` — keep it there rather than hard-coding
strings into views, since that is what would make re-adding a language a translation job rather
than a rewrite. `PeraPrompt::EXPLANATION_LANGUAGE_RULE` names English outright; it is **shared** with
the card generator so chat and cards cannot disagree. Do not reword it to follow the student's own
language: a learner practising writes Japanese, so "the language the student writes in" points at
the language being taught, and beginners got feedback they could not read.

**Frontend**: server-rendered ERB + Bootstrap 5 + Hotwire (Turbo + Stimulus) + importmap — no
Node/webpack/yarn build step. Forms use `simple_form`. Thirteen Stimulus controllers in
`app/javascript/controllers/` cover the chat UX (autogrow, enter-submit, char count, scroll,
reply streaming, flashcard streaming), studying (reveal, reveal-state), live search and dark mode. The app ships as a
PWA (`app/views/pwa/manifest.json.erb`, `service-worker.js`).

## Notes

- **`test/credentials_pinned_test.rb` is a safety guard, not a formality.** dotenv loads `.env` in
  the test environment, so any API-key variable `test_helper` forgets to pin arrives holding a real
  key. That has already happened: only singular `GEMINI_API_KEY` was pinned while `LlmChat.keys`
  reads `GEMINI_API_KEYS` first, and the suite spent live quota until a failure printed the key.
  Add every new key variable to both `test_helper` and that test's `VARIABLES`. Its assertions are
  bare `assert` with hand-written messages on purpose — `assert_equal` would print the live key into
  CI logs on exactly the run that proves it is exposed.
- Coverage: `test/models` for `Flashcard`, `Deck`, `Conversation`, `Message`, `Page`, `User`,
  `QuizQuestion`; `test/controllers` for flashcards, conversations and quizzes;
  `test/services` for `LlmChat`, `PeraPrompt` and `StreamedCards`; `test/system` for chatting,
  generating flashcards, studying, search, input box and phone layout; plus a PWA integration test. Not covered: `PeraReply` and the SSE
  path in `MessagesController`, `DecksController#export`, and all JS.
- The services in `app/services/` carry long comments explaining *why* each constant and structure
  is what it is. Read them before changing a number — most of them record a problem that was hit.
