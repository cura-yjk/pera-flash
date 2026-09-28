# Generates Pera's reply to one message, yielding it in pieces as the model
# produces them.
#
# Lives outside the controller because it is the only part of the exchange that
# is about teaching rather than about HTTP: which history to replay, what the
# student keeps forgetting, how much of the conversation the model is reminded
# of. The controller turns whatever comes back into server-sent events.
class PeraReply
  # How much of the conversation Pera is reminded of. Every reply replayed the
  # entire history, so the cost of a chat grew with the square of its length --
  # message fifty carried the preceding forty-nine with it. Recent turns are
  # what a tutor needs; the durable memory of what a learner struggles with
  # comes from their flashcards instead, which is bounded and cheaper.
  MAX_HISTORY_MESSAGES = 30

  # Enough for Pera to find an opening, few enough that the instructions stay
  # about teaching rather than becoming a list of failures.
  STRUGGLING_LIMIT = 5

  # Gemini stopped the reply itself -- finish_reason content_filter, which
  # ruby_llm also uses for RECITATION and the like. On 2026-09-26 and again on
  # 2026-09-27 it did so one token in, to "How does this app work?" and "What
  # should I learn first?", and "Hello" was saved as Pera's answer. Raised
  # rather than returned, so the controller treats it as the failure it is.
  class Blocked < StandardError; end

  # How long Pera waits for Gemini to say anything, in seconds. The app-wide
  # 30s (config/initializers/ruby_llm.rb) was also Heroku's limit for a first
  # byte, so waiting longer was pointless; the stream now opens at once and
  # keeps talking (EventStreaming#while_waiting), and on 2026-09-27 every
  # answer Gemini gave took 29 to 80 seconds. Waiting costs no quota -- it is
  # still one request.
  #
  # 120 rather than 90 since 2026-09-28: 3.5-flash was measured answering
  # after 93.9 seconds of silence, just past 90.
  TIMEOUT = 120

  # A busy Gemini (503) is not asked again. From 2026-09-27 it was, up to
  # three times with growing pauses, and on 2026-09-28 that turned one failure
  # into a minute of an answer being written, wiped and written again that
  # still ended in failure -- Gemini would write half an answer and then say
  # "busy" in the same stream. Busy is now told at once, with Try again; the
  # wait above is for an answer that is slow, not one that was refused.

  def initialize(conversation, question)
    @conversation = conversation
    @question = question
  end

  # Yields the reply so far each time it grows, and returns the whole of it.
  #
  # The reply so far rather than each new piece: a key that runs out of quota
  # partway through is swapped for the next (LlmChat), and the reply starts
  # over there. A caller adding pieces up would show it twice.
  #
  # on_restart is called when an answer starts over after some of it was
  # yielded, so the page can say why the text changed rather than rewinding it
  # silently (2026-09-28).
  def call(on_restart: nil, &on_text)
    raise ArgumentError, "PeraReply streams; pass a block to receive the text" unless on_text

    @on_restart = on_restart
    reply = logged { answer(&on_text) }
    # After the log line, so it still says how far the reply got and why.
    raise Blocked, "Gemini stopped the reply: #{@response.finish_reason}" if @response&.content_filtered?

    reply
  end

  private

  def answer(&on_text)
    LlmChat.with_chat(timeout: TIMEOUT) { |chat| collect(prepare(chat), &on_text) }
  end

  # One line per reply: how long it was, how long it took, and why Gemini
  # stopped -- :stop when it finished, :max_tokens when cut off, and so on.
  # Replies were not logged at all, so a reply of just "Hello" to "How does
  # this app work?" (2026-09-26) could not be told apart from one cut short.
  # Written from ensure, so a reply that raised is logged as failed.
  def logged
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    reply = yield
  ensure
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Rails.logger.info("Pera reply for conversation #{@conversation.id}: " \
                      "#{reply.nil? ? 'failed' : "#{reply.size} characters"} in #{elapsed}ms#{ending(reply)}")
  end

  def ending(reply)
    return "" if reply.nil?

    tokens = @response&.tokens
    ", finished: #{@response&.finish_reason || 'unknown'}, " \
      "tokens in/out: #{tokens&.input || '?'}/#{tokens&.output || '?'}"
  end

  def prepare(chat)
    chat.with_instructions(PeraPrompt.for(struggling: struggling_cards))
    replay_history(chat)
    chat
  end

  def collect(chat)
    started_over
    reply = +""

    @response = chat.ask(@question.content) do |chunk|
      text = chunk.content.to_s
      next if text.empty?

      reply << text
      @shown = true
      yield reply.dup
    end

    reply
  end

  # Each attempt begins in collect, so an earlier one having shown text means
  # this one is starting over.
  def started_over
    return unless @shown

    @shown = false
    @on_restart&.call
  end

  # The newest MAX_HISTORY_MESSAGES, replayed oldest-first.
  #
  # Excludes the message being answered: it is already saved by the time this
  # runs, and #ask sends it too, so the model was being shown every new message
  # twice.
  def replay_history(chat)
    @conversation.messages
                 .where.not(id: @question.id)
                 .order(created_at: :desc)
                 .limit(MAX_HISTORY_MESSAGES)
                 .reverse_each { |message| chat.add_message(role: message.role, content: message.content) }
  end

  # Across every deck, not just this conversation: what someone keeps
  # forgetting is a fact about them, not about where the card came from.
  def struggling_cards
    Flashcard.for_user(@conversation.user).struggling.limit(STRUGGLING_LIMIT)
  end
end
