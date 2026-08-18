class ConversationsController < ApplicationController

  def show
    @conversation = current_user.conversations.find(params[:id])
    @message = Message.new

  def create
    @conversation = Conversation.new
    if @conversation.save
      redirect_to conversation_path(@conversation)
    else
      render "pages/home", status: :unprocessable_entity
    end
  end
end
