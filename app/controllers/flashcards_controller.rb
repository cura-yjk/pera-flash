class FlashcardsController < ApplicationController
  def create
    conversation = current_user.conversations.find(params[:conversation_id])
    cards = params.require(:conversation).permit(flashcards: %i[question answer])

    cards[:flashcards].each_value { |card| conversation.flashcards.create!(card) }
    Message.create(
      content: "flashcards created!",
      role: 'assistant',
      conversation: conversation
    )
    redirect_to conversation_path(conversation), notice: "Flashcards saved!"
  end
end
