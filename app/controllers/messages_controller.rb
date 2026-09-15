class MessagesController < ApplicationController
  # Enough for Pera to find an opening, few enough that the instructions
  # stay about teaching rather than becoming a list of failures.
  STRUGGLING_LIMIT = 5

  # How much of the conversation Pera is reminded of. Every reply replayed the
  # entire history, so the cost of a chat grew with the square of its length --
  # message fifty carried the preceding forty-nine with it. Recent turns are
  # what a tutor needs; the durable memory of what a learner struggles with
  # comes from their flashcards instead, which is bounded and cheaper.
  MAX_HISTORY_MESSAGES = 30

  # Every message here is an LLM call, so this is where a script runs up a
  # bill. Two layers by account -- a burst nobody types through, and an hourly
  # ceiling a patient script still cannot cross -- plus a per-IP hourly cap,
  # since signup is open and one person can hold many accounts.
  rate_limit to: 15, within: 1.minute,
             by: -> { current_user.id }, with: -> { rate_limited }, name: "messages_burst"
  rate_limit to: 200, within: 1.hour,
             by: -> { current_user.id }, with: -> { rate_limited }, name: "messages_hourly"
  rate_limit to: 400, within: 1.hour,
             by: -> { request.remote_ip }, with: -> { rate_limited }, name: "messages_by_ip"

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
    chat = LlmChat.new_chat
    replay_history(chat, message)
    chat.with_instructions(Message.system_prompt(struggling: struggling_cards)).ask(message.content).content
  rescue StandardError => e
    Rails.logger.error("Pera could not reply in conversation #{@conversation.id}: #{e.class}: #{e.message}")
    nil
  end

  # Across every deck, not just this conversation: what someone keeps
  # forgetting is a fact about them, not about where the card came from.
  def struggling_cards
    Flashcard.for_user(current_user).struggling.limit(STRUGGLING_LIMIT)
  end

  # The newest MAX_HISTORY_MESSAGES, replayed oldest-first.
  #
  # Excludes the message being answered: it is already saved by the time this
  # runs, and #ask sends it too, so the model was being shown every new message
  # twice.
  def replay_history(chat, current_message)
    @conversation.messages
                 .where.not(id: current_message.id)
                 .order(created_at: :desc)
                 .limit(MAX_HISTORY_MESSAGES)
                 .reverse_each { |message| chat.add_message(role: message.role, content: message.content) }
  end

  def rate_limited
    notice = "You are sending messages faster than Pera can answer them. Give it a moment."

    respond_to do |format|
      format.turbo_stream { render :rate_limited, locals: { notice: notice }, status: :too_many_requests }
      format.html { redirect_back fallback_location: dashboard_path, alert: notice }
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
