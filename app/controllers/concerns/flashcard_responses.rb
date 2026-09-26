# How ConversationsController#generate_flashcards answers: streamed card by
# card or whole, and failed, cards, or nothing worth a card. The action
# decides what to generate from; this is everything after that.
#
# Relies on EventStreaming for the stream, and on @conversation.
module FlashcardResponses
  extend ActiveSupport::Concern

  private

  # The browser lists text/event-stream first when it can read a stream, and
  # turbo_stream after it for the responses that are not one.
  def streaming_requested?
    request.headers["Accept"].to_s.include?("text/event-stream")
  end

  # Generation shows nothing until the whole JSON list is written, and its time
  # grows with every card. Streamed, each card is sent as soon as it is
  # complete: the first appears after a second or two rather than after all of
  # them. It also keeps Heroku from ending a slow generation at 30 seconds,
  # which only applies until the first byte is sent.
  #
  # Events: "open" (the preview, empty), "card" (one card), "reset" (a retry
  # on the next API key is starting over), then "done" or "failed".
  def stream_flashcards(generation)
    prepare_event_stream
    send_event("open", html: preview_html)
    cards = unless_failed { stream_cards(generation) }
    send_event(*outcome(cards))
  rescue EventStreaming::Stop
    nil
  ensure
    response.stream.close
  end

  def stream_cards(generation)
    generation.stream(on_reset: -> { send_event("reset", {}) }) do |card, index|
      send_event("card", html: card_html(card, index))
    end
  end

  # How a streamed generation ended: failed, cards, or nothing worth a card.
  def outcome(cards)
    return ["failed", { html: failed_html }] if cards.nil?
    return ["done", { count: cards.size }] if cards.any?

    @conversation.mark_carded!
    ["empty", { html: nothing_to_card_html }]
  end

  # A generation that worked and found nothing to card -- small talk, or
  # questions about the app. It used to open an empty preview with Save
  # enabled, and Save with nothing in it was a 400. The batch is marked done,
  # so tapping again says "all caught up" instead of paying to read the same
  # messages; anything said afterwards is new material as usual.
  def render_nothing_to_card
    @conversation.mark_carded!
    render :nothing_to_card
  end

  # The generation's result, or nil when the provider could not be reached --
  # the conversation is untouched either way, so the learner can simply try
  # again. @failure says why, for the notice (LlmFailure). Stop is let
  # through: it means the browser left, not that Gemini did.
  def unless_failed
    yield
  rescue EventStreaming::Stop
    raise
  rescue StandardError => e
    Rails.logger.error("Could not generate flashcards for conversation #{@conversation.id}: " \
                       "#{e.class}: #{e.message}")
    @failure = LlmFailure.reason(e)
    nil
  end

  def preview_html
    render_to_string(partial: "conversations/flashcard_preview", formats: [:html],
                     locals: { conversation: @conversation, flashcards: [], streaming: true })
  end

  def card_html(flashcard, index)
    render_to_string(partial: "conversations/flashcard_preview_card", formats: [:html],
                     locals: { flashcard: flashcard, index: index })
  end

  def failed_html
    render_to_string(partial: "conversations/generation_failed", formats: [:html],
                     locals: { reason: @failure, conversation: @conversation })
  end

  def nothing_to_card_html
    render_to_string(partial: "conversations/nothing_to_card", formats: [:html])
  end
end
