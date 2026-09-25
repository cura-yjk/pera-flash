# Turns what was said in a chat into flashcards: the prompt, the request, and
# the limits. Whole (#call), or card by card as each is written (#stream).
#
# Raises when the provider cannot be reached, and leaves what the learner sees
# to the controller. Either way, every generation logs one line: see #timed.
class FlashcardGeneration
  def initialize(conversation, messages)
    @conversation = conversation
    @messages = messages
  end

  # The cards, built but not saved.
  def call
    timed do
      response = LlmChat.with_chat { |chat| chat.with_schema(FlashcardsSchema).ask(prompt) }

      # #parsed, not #content: ruby_llm 2.0 returns a schema response as the raw
      # JSON string, and String#[] with a key is a substring match -- so
      # content["flashcards"] gave back the word "flashcards" and every card
      # arrived blank. Trimmed as well as asked for: the schema's maxItems and
      # the prompt both say ten, but a model can ignore either.
      Array(response.parsed&.dig("flashcards")).first(FlashcardsSchema::MAX_CARDS).map { |card| build(card) }
    end
  end

  # Yields each card, with its position, as soon as it is complete, and returns
  # them all at the end. on_reset is called when a retry on the next API key
  # starts the list again, so cards already shown can be taken away.
  def stream(on_reset: nil, &on_card)
    timed do
      cards = []
      LlmChat.with_chat do |chat|
        on_reset&.call if cards.any?
        cards.clear
        stream_from(chat, cards, &on_card)
      end
      cards
    end
  end

  private

  def stream_from(chat, cards)
    parser = StreamedCards.new

    chat.with_schema(FlashcardsSchema).ask(prompt) do |chunk|
      parser.push(chunk.content.to_s) do |card|
        next if cards.size >= FlashcardsSchema::MAX_CARDS

        cards << build(card)
        yield cards.last, cards.size - 1
      end
    end
  end

  def build(card)
    @conversation.flashcards.build(question: card["question"], answer: card["answer"])
  end

  def transcript
    @transcript ||= @messages.map { |m| "#{m.role}: #{m.content}" }.join("\n\n")
  end

  # One line per generation, with what went in and how long it took.
  # Generation was "slow sometimes" and nothing recorded when, or with what:
  # the request log only shows the total, and Heroku keeps too few lines to
  # find it again. This is the line to grep for. Written from ensure, so a
  # generation that raised is logged as failed rather than not at all.
  def timed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    cards = yield
  ensure
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    Rails.logger.info("Flashcard generation for conversation #{@conversation.id}: " \
                      "#{cards.nil? ? 'failed' : "#{cards.size} cards"} in #{elapsed}ms " \
                      "from #{@messages.size} messages (#{transcript.size} characters)")
  end

  # The transcript is already scoped to new material, so this no longer has to
  # ask the model to focus on recent topics or avoid the existing cards -- it
  # cannot see the old material to repeat it.
  def prompt
    <<~PROMPT
      Based on the conversation below, generate flashcards covering the key Japanese vocabulary, grammar, or concepts discussed. Generate one per distinct concept actually covered -- if the conversation covered two things, return two cards. Never invent filler or pad with near-duplicates. Return at most #{FlashcardsSchema::MAX_CARDS} cards; if more concepts were covered, choose the #{FlashcardsSchema::MAX_CARDS} most useful for a beginner to remember.

      #{PeraPrompt::EXPLANATION_LANGUAGE_RULE}

      #{PeraPrompt::FURIGANA_RULE}
      Guidelines:
      - Question = a clear prompt testing recall (e.g., "What does 猫 mean?" or "How do you say 'I like cats' in Japanese?").
      - Answer = concise, correct answer.
      - Keep difficulty appropriate for a beginner (hiragana/katakana known, minimal kanji/grammar).
      - The first message may be lead-in context from earlier. Only card it if the exchange below actually teaches it.
      - If nothing here teaches a distinct concept, return an empty array.

      Conversation:
      #{transcript}
    PROMPT
  end
end
