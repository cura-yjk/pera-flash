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
  TIMEOUT = 90

  # How many more times to ask when Gemini answers "experiencing high demand"
  # (503). On 2026-09-27 that was most of the failures, some after 15 to 27
  # seconds of waiting, and moodwalk -- same model, same evening -- got its
  # answers because ruby_llm's default retries asked again. Retries are off
  # app-wide (config/initializers/ruby_llm.rb), so a timeout still costs one
  # request; this bends that for "busy" alone, because it is the one failure
  # that asking again a moment later often fixes.
  #
  # All attempts share TIMEOUT, since the learner is watching the whole time,
  # and one is not started with less than MIN_ATTEMPT_SECONDS left.
  BUSY_RETRIES = 3
  MIN_ATTEMPT_SECONDS = 10

  # The pause before each retry, growing. A flat 2s spent all four attempts in
  # under ten seconds (2026-09-27, locally) -- shorter than Gemini stays busy --
  # while Try again forty seconds later was answered. These spread them over
  # about thirty. A setting so the tests need not sleep.
  cattr_accessor :busy_pauses, default: [3, 8, 15]

  def initialize(conversation, question)
    @conversation = conversation
    @question = question
  end

  # Yields the reply so far each time it grows, and returns the whole of it.
  #
  # The reply so far rather than each new piece: a busy Gemini is asked again,
  # and a key out of quota is swapped for the next (LlmChat), and either way the
  # reply starts over. A caller adding pieces up would show it twice.
  def call(&on_text)
    raise ArgumentError, "PeraReply streams; pass a block to receive the text" unless on_text

    reply = logged { answer(&on_text) }
    # After the log line, so it still says how far the reply got and why.
    raise Blocked, "Gemini stopped the reply: #{@response.finish_reason}" if @response&.content_filtered?

    reply
  end

  private

  def answer(&on_text)
    deadline = Time.current + TIMEOUT
    attempt = 1

    begin
      LlmChat.with_chat(timeout: (deadline - Time.current).ceil) { |chat| collect(prepare(chat), &on_text) }
    rescue RubyLLM::ServiceUnavailableError, RubyLLM::OverloadedError
      raise unless ask_again?(attempt, deadline)

      attempt += 1
      retry
    end
  end

  def ask_again?(attempt, deadline)
    return false if attempt > BUSY_RETRIES || deadline - Time.current < MIN_ATTEMPT_SECONDS

    Rails.logger.warn("Gemini busy for conversation #{@conversation.id} " \
                      "(attempt #{attempt} of #{1 + BUSY_RETRIES}); asking again")
    sleep busy_pauses.fetch(attempt - 1, busy_pauses.last)
    true
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
    chat.with_instructions(PeraPrompt.for(struggling: struggling_cards,
                                          greet: first_words?))
    replay_history(chat)
    chat
  end

  def collect(chat)
    reply = +""

    @response = chat.ask(@question.content) do |chunk|
      text = chunk.content.to_s
      next if text.empty?

      reply << text
      yield reply.dup
    end

    reply
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

  # Whether Pera has spoken here yet. Asked because the introduction is worth
  # requesting once and then never again: the model cannot tell, since the
  # history it sees is capped and the greeting eventually scrolls out of it.
  def first_words?
    @conversation.messages.where(role: "assistant").none?
  end

  # Across every deck, not just this conversation: what someone keeps
  # forgetting is a fact about them, not about where the card came from.
  def struggling_cards
    Flashcard.for_user(@conversation.user).struggling.limit(STRUGGLING_LIMIT)
  end
end
