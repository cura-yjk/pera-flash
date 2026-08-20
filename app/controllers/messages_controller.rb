class MessagesController < ApplicationController
  def create # rubocop:disable Metrics/MethodLength
    @conversation = Conversation.find(params[:conversation_id])

    @message = Message.new(message_params)
    @message.conversation = @conversation
    @message.role = "user"

    if @message.save
      @ruby_llm = RubyLLM.chat
      build_conversation_history
      response = @ruby_llm.with_instructions(Message.system_prompt).ask(@message.content)
      @assistant_message = @conversation.messages.create(
        content: response.content,
        role: 'assistant',
        conversation: @conversation
      )

      @conversation.generate_title_from_first_message if @conversation.messages.where(role: "user").count == 1

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to conversation_path(@conversation) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("new_message_container", partial: "messages/form",
                                                                            locals: { conversation: @conversation, message: @message })
        end
        format.html { render "chats/show", status: :unprocessable_entity }
      end
    end
  end

  def build_conversation_history
    @conversation.messages.each do |message|
      @ruby_llm.add_message(role: message.role, content: message.content)
    end
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end
