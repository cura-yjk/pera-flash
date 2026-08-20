# Handles the "chat with AI to learn Japanese, then turn it into flashcards" flow
class ConversationsController < ApplicationController
  # Show a single conversation and its message history, plus a blank
  # Message for the reply form on the page
  def show
    @conversation = current_user.conversations.find(params[:id])
    @messages = @conversation.messages.order(:created_at)
    @message = Message.new
  end

  # Start a new, empty conversation for the current user
  def create
    current_user.conversations.empty.destroy_all
    @conversation = current_user.conversations.empty.first || current_user.conversations.new
    if @conversation.persisted? || @conversation.save
      redirect_to conversation_path(@conversation)
    else
      # No dedicated "new" view/route, so fall back to re-rendering the
      # home page (where conversations presumably get kicked off) on failure
      render "pages/home", status: :unprocessable_entity
    end
  end

  # Given an existing conversation, ask the LLM to turn it into 3-5 flashcards
  # and build (but not yet save) them as associated Flashcard records
  def generate_flashcards # rubocop:disable Metrics/MethodLength
    @conversation = current_user.conversations.find(params[:id])

    # Flatten the message history into a plain "role: content" transcript
    # to feed to the LLM as context
    transcript = @conversation.messages.order(:created_at)
                              .map { |m| "#{m.role}: #{m.content}" }.join("\n\n")

    # Ask the LLM for flashcards, constrained to a JSON schema (FlashcardsSchema)
    # so the response comes back structured rather than free text
    response = RubyLLM.chat.with_schema(FlashcardsSchema).ask(<<~PROMPT)
      Based on the conversation below, generate 3-5 flashcards covering the key Japanese vocabulary, grammar, or concepts discussed. Only generate flashcards for concepts that were actually covered — if fewer than 3 distinct concepts exist, return fewer rather than inventing filler or padding with near-duplicates.

      Language: Write the question and answer text (not the Japanese content itself) in the same language predominantly used in the conversation below. Japanese words/sentences being taught always stay in Japanese with romaji; only the surrounding question/explanation language should match the conversation's language. If the conversation mixes languages inconsistently, default to English.

      Guidelines:
      - Question = a clear prompt testing recall (e.g., "What does 猫 mean?" or "How do you say 'I like cats' in Japanese?").
      - Answer = concise, correct answer. Include romaji for any Japanese word or phrase in the answer.
      - Keep difficulty appropriate for a beginner (hiragana/katakana known, minimal kanji/grammar).
      - Do not duplicate or closely rephrase any of these existing flashcard questions: #{@conversation.flashcards.pluck(:question).join(', ')}
      - If the conversation didn't cover any new distinct concepts beyond the existing flashcards, return an empty array instead of forcing new ones.

      Return ONLY valid JSON in this exact format, no other text:
      [
        { "question": "...", "answer": "..." }
      ]

      Conversation:
      #{transcript}
    PROMPT

    # Build (not save) a Flashcard per item returned, associated to this
    # conversation — presumably rendered for the user to review/confirm
    # before they're persisted (see flashcards#create, "step 6")
    @flashcards = response.content["flashcards"].map do |card|
      @conversation.flashcards.build(question: card["question"], answer: card["answer"])
    end
  end
end
