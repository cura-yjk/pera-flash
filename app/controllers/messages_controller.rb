class MessagesController < ApplicationController
  def create
    # Scoped to the signer-in: this was a bare Conversation.find, the only one
    # in the app, so any signed-in user could post into someone else's chat.
    @conversation = current_user.conversations.find(params[:conversation_id])

    @message = @conversation.messages.new(message_params.merge(role: "user"))

    return render_invalid unless @message.save

    return render_reply_failed unless answered?(@message)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to conversation_path(@conversation) }
    end
  end

  private

  # True once Pera has answered and the reply is saved.
  def answered?(message)
    reply = generate_reply(message)
    return false if reply.nil?

    @assistant_message = @conversation.messages.create!(content: reply, role: "assistant")
    @conversation.generate_title_from_first_message if first_exchange?
    true
  end

  # Returns the reply text, or nil if the provider could not give us one.
  #
  # The user's message is already saved by this point, so a failure here must
  # not take the request down with it: they would watch their message land and
  # then get an error page, with no reply and no way back.
  def generate_reply(message)
    chat = RubyLLM.chat
    replay_history(chat)
    chat.with_instructions(Message.system_prompt).ask(message.content).content
  rescue StandardError => e
    Rails.logger.error("Pera could not reply in conversation #{@conversation.id}: #{e.class}: #{e.message}")
    nil
  end

  def replay_history(chat)
    @conversation.messages.order(:created_at).each do |message|
      chat.add_message(role: message.role, content: message.content)
    end
  end

  def first_exchange?
    @conversation.messages.where(role: "user").one?
  end

  def render_reply_failed
    respond_to do |format|
      format.turbo_stream { render :reply_failed }
      format.html do
        redirect_to conversation_path(@conversation),
                    alert: "Pera could not reply just now. Your message was saved -- try again."
      end
    end
  end

  def render_invalid
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "new_message_container",
          partial: "messages/form",
          locals: { conversation: @conversation, message: @message }
        )
      end
      format.html { render "conversations/show", status: :unprocessable_entity }
    end
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
