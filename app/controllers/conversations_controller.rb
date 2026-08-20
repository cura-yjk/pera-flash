class ConversationsController < ApplicationController
  def show
    @conversation = current_user.conversations.find(params[:id])
    @messages = @conversation.messages.order(:created_at)
    @message = Message.new
  end

  def create
    @conversation = Conversation.new
    @conversation.user = current_user
    if @conversation.save
      redirect_to conversation_path(@conversation)
    else
      render "pages/home", status: :unprocessable_entity
    end
  end

  def generate_flashcards # rubocop:disable Metrics/MethodLength
    @conversation = current_user.conversations.find(params[:id])
    transcript = @conversation.messages.order(:created_at)
                              .map { |m| "#{m.role}: #{m.content}" }.join("\n\n")

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

    @flashcards = response.content["flashcards"].map do |card|
      @conversation.flashcards.build(question: card["question"], answer: card["answer"])
    end
  end
end
