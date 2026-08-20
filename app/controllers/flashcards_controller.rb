class FlashcardsController < ApplicationController
  def create
    conversation = current_user.conversations.find(params[:conversation_id])
    cards = params.require(:conversation).permit(flashcards: %i[question answer])

    created = cards[:flashcards].each_value.map { |card| conversation.flashcards.create!(card) }

    Message.create!(
      content: "✅ #{created.size} cards added! [View your flashcards](#{flashcards_path})",
      role: 'assistant',
      conversation: conversation
    )

    redirect_to conversation_path(conversation), notice: "Flashcards saved!"
  end

  def index
    @flashcards = Flashcard.where(conversation: current_user.conversations)

    return unless params[:query].present?

    @flashcards = @flashcards.where("question ILIKE :q OR answer ILIKE :q", q: "%#{params[:query]}%")
  end

  def edit
    @flashcard = current_user_flashcard(params[:id])
  end

  def update
    @flashcard = current_user_flashcard(params[:id])
    if @flashcard.update(flashcard_params)
      redirect_back fallback_location: flashcards_path, notice: "Flashcard updated!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
  end

  private

  def flashcard_params
    params.require(:flashcard).permit(:question, :answer)
  end

  def current_user_flashcard(id)
    Flashcard.left_joins(:deck, :conversation)
             .where("decks.user_id = :uid OR conversations.user_id = :uid", uid: current_user.id)
             .find(id)
  end
end
