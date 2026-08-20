class FlashcardsController < ApplicationController
  def create
    conversation = current_user.conversations.find(params[:conversation_id])
    cards = params.require(:conversation).permit(flashcards: %i[question answer])

    deck = current_user.decks.find_or_create_by!(name: conversation.title.presence || "Untitled Deck")

    created = cards[:flashcards].each_value.map { |card| conversation.flashcards.create!(card.merge(deck: deck)) }

    Message.create!(
      content: "✅ #{created.size} cards added! [View your flashcards](#{flashcards_path})",
      role: 'assistant',
      conversation: conversation
    )

    redirect_to conversation_path(conversation), notice: "Flashcards saved!"
  end

  def index
    @flashcards = Flashcard.where(conversation: current_user.conversations).order(created_at: :desc)

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
      redirect_to flashcards_path, notice: "Flashcard updated!"
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

  def flashcard_params
    params.require(:flashcard).permit(:question, :answer, :deck_id)
  end

  def current_user_flashcard(id)
    Flashcard.left_joins(:deck, :conversation)
             .where("decks.user_id = :uid OR conversations.user_id = :uid", uid: current_user.id)
             .find(id)
  end
end
