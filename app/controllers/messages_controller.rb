class MessagesController < ApplicationController
  def create # rubocop:disable Metrics/MethodLength
    @conversation = Conversation.find(params[:conversation_id])

    @message = Message.new(message_params)
    @message.conversation = @conversation
    @message.role = "user"

    if @message.save
      chat = RubyLLM.chat
      chat.with_instructions(Message.system_prompt)
      response = chat.ask(@message.content)
      Message.create(
        content: response.content,
        role: 'assistant',
        chat: @conversation
      )
      redirect_to conversation_path(@conversation)
    else
      render "conversations/show", status: :unprocessable_entity
    end
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end
