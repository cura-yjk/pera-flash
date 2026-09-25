# Handles the "chat with AI to learn Japanese, then turn it into flashcards" flow
class ConversationsController < ApplicationController
  # A generation is a second LLM call per press, and the button sits right in
  # the chat -- cheaper to press repeatedly than to type a message.
  # `only:` is not optional here: without it these throttle every action in the
  # controller, so the sixth conversation you merely *open* is refused.
  rate_limit to: 5, within: 1.minute, only: :generate_flashcards,
             by: -> { current_user.id }, with: -> { generation_rate_limited }, name: "generate_burst"
  rate_limit to: 60, within: 1.hour, only: :generate_flashcards,
             by: -> { current_user.id }, with: -> { generation_rate_limited }, name: "generate_hourly"
  # Creating a conversation costs no LLM call, only rows -- limited to keep a
  # script from filling the table.
  rate_limit to: 20, within: 1.minute, by: -> { current_user.id }, only: :create

  # Every chat the user has actually used, newest first. The navbar's "Chat
  # History" link pointed at href="#" until this existed.
  def index
    @page = Page.of(current_user.conversations.started.order(created_at: :desc), params[:page])
    @conversations = @page.records
  end

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

  # The rename form, shown in place of the title (see _title.html.erb).
  def edit
    @conversation = current_user.conversations.find(params[:id])
  end

  # Back to the chat either way it is reached: inside the title's turbo frame,
  # Turbo follows the redirect and takes just the frame from the page.
  def update
    @conversation = current_user.conversations.find(params[:id])

    if @conversation.update(params.require(:conversation).permit(:title))
      redirect_to conversation_path(@conversation), status: :see_other
    else
      render :edit, status: :unprocessable_entity
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
    render :generation_failed if @flashcards.nil?
  end

  private

  def generation_rate_limited
    notice = t("conversations.rate_limited")

    respond_to do |format|
      format.turbo_stream { render :generation_rate_limited, locals: { notice: notice }, status: :too_many_requests }
      format.html { redirect_back fallback_location: dashboard_path, alert: notice }
    end
  end

  def transcript_of(messages)
    messages.map { |m| "#{m.role}: #{m.content}" }.join("\n\n")
  end

  # Returns the built (unsaved) cards, or nil when the provider could not be
  # reached -- the conversation is untouched either way, so the learner can
  # simply try again.
  def build_flashcards(transcript)
    response = LlmChat.with_chat { |chat| chat.with_schema(FlashcardsSchema).ask(flashcard_prompt(transcript)) }

    # #parsed, not #content: ruby_llm 2.0 returns a schema response as the raw
    # JSON string, and String#[] with a key is a substring match -- so
    # content["flashcards"] gave back the word "flashcards" and every card
    # arrived blank.
    Array(response.parsed&.dig("flashcards")).map do |card|
      @conversation.flashcards.build(question: card["question"], answer: card["answer"])
    end
  rescue StandardError => e
    Rails.logger.error("Could not generate flashcards for conversation #{@conversation.id}: " \
                       "#{e.class}: #{e.message}")
    nil
  end

  # The transcript is already scoped to new material, so this no longer has to
  # ask the model to focus on recent topics or avoid the existing cards -- it
  # cannot see the old material to repeat it.
  def flashcard_prompt(transcript)
    <<~PROMPT
      Based on the conversation below, generate flashcards covering the key Japanese vocabulary, grammar, or concepts discussed. Generate one per distinct concept actually covered -- if the conversation covered two things, return two cards. Never invent filler or pad with near-duplicates.

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
