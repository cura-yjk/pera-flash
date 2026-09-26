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

  def initialize(conversation, question)
    @conversation = conversation
    @question = question
  end

  # Yields each piece of text as it arrives and returns the whole reply.
  #
  # If a key runs out of quota mid-exchange, LlmChat retries on the next one and
  # this starts over -- hence resetting the accumulated reply inside the block.
  # The browser is sent the whole reply-so-far on every update, so a restart
  # redraws rather than doubling the text.
  def call(&on_text)
    raise ArgumentError, "PeraReply streams; pass a block to receive the text" unless on_text

    logged { LlmChat.with_chat { |chat| collect(prepare(chat), &on_text) } }
  end

  private

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
      yield text
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
