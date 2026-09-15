class MessagesController < ApplicationController
  # Pera's reply is streamed token by token rather than delivered whole, the
  # way every chat interface does it. #create no longer waits for the model: it
  # saves what the student wrote and hands back an empty bubble, which #stream
  # then fills over an SSE connection.
  include ActionController::Live

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

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to conversation_path(@conversation) }
    end
  end

  # The reply itself, streamed as it is generated.
  #
  # A GET with no side effect the student can trigger twice: it only answers
  # when the conversation is actually waiting for one, so reloading or replaying
  # this URL cannot spend a second generation on the same message.
  def stream
    @conversation = current_user.conversations.find(params[:conversation_id])
    question = unanswered_message(@conversation)

    return head :no_content if question.nil?

    prepare_event_stream

    # The ensure belongs to the streaming, not to the whole action: wrapping the
    # lookup above meant a 404 closed the stream on its way out, committing a
    # 200 before the RecordNotFound could be turned into a response.
    begin
      stream_reply(question)
    ensure
      response.stream.close
    end
  end

  private

  # Nothing between here and the browser may buffer, or the tokens arrive in one
  # lump at the end and the streaming is pointless.
  def prepare_event_stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
  end

  # The last message, if it is a question nobody has answered yet.
  def unanswered_message(conversation)
    last = conversation.messages.order(:created_at).last

    last if last&.user?
  end

  # Sends each token as it arrives, then one final event carrying the saved
  # message rendered properly -- markdown, tables and furigana, which cannot be
  # rendered from a half-finished string mid-stream.
  def stream_reply(question)
    reply = +""

    finish_reply(PeraReply.new(@conversation, question).call do |text|
      reply << text
      # Re-rendered each update rather than sent as plain text: watching raw
      # markdown scroll past and then be rewritten is worse than a table that
      # is briefly one row short. Costs a few milliseconds and keeps one
      # rendering path, so what streams in is what gets kept.
      send_event("chunk", html: helpers.chat_html(reply))
    end)
  rescue Stop
    # The student navigated away mid-reply. Nothing to report and nothing to
    # save -- the next thing they send starts a fresh exchange.
    nil
  rescue StandardError => e
    # The student's message is already saved, so a failure here must not lose
    # it: they see a notice and can send it again.
    Rails.logger.error("Pera could not reply in conversation #{@conversation.id}: #{e.class}: #{e.message}")
    send_event("failed", {})
  end

  def finish_reply(reply)
    return send_event("failed", {}) if reply.blank?

    message = @conversation.messages.create!(content: reply, role: "assistant")
    @conversation.generate_title_from_first_message if first_exchange?

    send_event("done", html: render_to_string(partial: "messages/message", formats: [:html],
                                              locals: { message: message }),
                       title: @conversation.reload.title)
  end

  # A client that has navigated away closes the socket mid-write; that is an
  # ordinary end to a stream, not an error worth reporting.
  def send_event(name, payload)
    response.stream.write("event: #{name}\ndata: #{payload.to_json}\n\n")
  rescue ActionController::Live::ClientDisconnected, IOError
    raise Stop
  end

  # Raised to unwind out of the streaming block when the client has gone.
  class Stop < StandardError; end

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
