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

  # Turn what has been discussed since the last generation into flashcards.
  #
  # Deliberately not the whole conversation: see
  # Conversation#messages_for_flashcards for why the input is scoped.
  def generate_flashcards
    @conversation = current_user.conversations.find(params[:id])
    messages = @conversation.messages_for_flashcards

    # Nothing said since the last batch -- answer without paying for a
    # generation that could only return an empty array.
    return render :no_new_material if messages.none?

    @flashcards = build_flashcards(transcript_of(messages))
  end

  private

  def transcript_of(messages)
    messages.map { |m| "#{m.role}: #{m.content}" }.join("\n\n")
  end

  def build_flashcards(transcript)
    response = RubyLLM.chat.with_schema(FlashcardsSchema).ask(flashcard_prompt(transcript))

    Array(response.content["flashcards"]).map do |card|
      @conversation.flashcards.build(question: card["question"], answer: card["answer"])
    end
  end

  # The transcript is already scoped to new material, so this no longer has to
  # ask the model to focus on recent topics or avoid the existing cards -- it
  # cannot see the old material to repeat it.
  def flashcard_prompt(transcript)
    <<~PROMPT
      Based on the conversation below, generate flashcards covering the key Japanese vocabulary, grammar, or concepts discussed. Generate one per distinct concept actually covered -- if the conversation covered two things, return two cards. Never invent filler or pad with near-duplicates.

      Language: Write the question and answer text (not the Japanese content itself) in the same language predominantly used in the conversation below. Japanese words/sentences being taught always stay in Japanese with romaji; only the surrounding question/explanation language should match the conversation's language. If the conversation mixes languages inconsistently, default to English.

      Guidelines:
      - Question = a clear prompt testing recall (e.g., "What does 猫 mean?" or "How do you say 'I like cats' in Japanese?").
      - Answer = concise, correct answer. Include romaji for any Japanese word or phrase in the answer.
      - Keep difficulty appropriate for a beginner (hiragana/katakana known, minimal kanji/grammar).
      - The first message may be lead-in context from earlier. Only card it if the exchange below actually teaches it.
      - If nothing here teaches a distinct concept, return an empty array.

      Conversation:
      #{transcript}
    PROMPT
  end
end
