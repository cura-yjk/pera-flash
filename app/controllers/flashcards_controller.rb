class FlashcardsController < ApplicationController
  # A generation returns a handful of cards; this is the ceiling on what one
  # request may write, since the list comes from the client rather than from
  # the generation that produced it.
  MAX_CARDS_PER_SAVE = 50

  rate_limit to: 30, within: 1.minute, by: -> { current_user.id }, only: :create

  def create
    conversation = current_user.conversations.find(params[:conversation_id])
    cards = params.require(:conversation).permit(flashcards: %i[question answer])

    return head :unprocessable_entity if cards[:flashcards].to_h.size > MAX_CARDS_PER_SAVE

    created = save_cards(conversation, cards[:flashcards])
    @message = confirmation_message(conversation, created.size)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to conversation_path(conversation), notice: t("flashcards.saved") }
    end
  end

  def index
    @flashcards = Flashcard.for_user(current_user).order(created_at: :desc)

    return unless params[:query].present?

    @flashcards = @flashcards.where("question ILIKE :q OR answer ILIKE :q", q: "%#{params[:query]}%")
  end

  def edit
    @flashcard = current_user_flashcard(params[:id])
    @decks = current_user.decks
  end

  def update
    @flashcard = current_user_flashcard(params[:id])
    if @flashcard.update(flashcard_params)
      redirect_to flashcards_path, notice: t("flashcards.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @flashcard = current_user_flashcard(params[:id])
    @flashcard.destroy!
    redirect_to request.referer || flashcards_path, notice: "Flashcard deleted."
  end

  private

  # A conversation's cards land in a deck named after it, created on first save.
  def save_cards(conversation, cards)
    deck = current_user.decks.find_or_create_by!(name: conversation.title.presence || "Untitled Deck")

    cards.each_value.map { |card| conversation.flashcards.create!(card.merge(deck: deck)) }
  end

  # Shown in the chat as a system notification -- see messages/_message.
  def confirmation_message(conversation, count)
    Message.create!(
      content: "✅ #{t('flashcards.added', count: count, path: flashcards_path)}",
      role: "assistant",
      conversation: conversation
    )
  end

  def flashcard_params
    params.require(:flashcard).permit(:question, :answer, :deck_id)
  end

  def current_user_flashcard(id)
    Flashcard.for_user(current_user).find(id)
  end
end
