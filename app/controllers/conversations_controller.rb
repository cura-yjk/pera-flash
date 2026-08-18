class ConversationsController < ApplicationController
  def create
    @conversation = Conversation.new
    if @conversation.save
      redirect_to conversation_path(@conversation)
    else
      render "pages/home", status: :unprocessable_entity
    end
  end
end
