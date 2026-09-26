# Server-sent events over ActionController::Live: Pera's replies
# (MessagesController) and generated flashcards (ConversationsController).
#
# Including this makes every action in the controller a Live action -- run on
# its own thread, its response streamed. Ordinary renders still work; that is
# how MessagesController has always run.
module EventStreaming
  extend ActiveSupport::Concern

  included do
    include ActionController::Live
  end

  # Raised to unwind out of the streaming block when the client has gone.
  class Stop < StandardError; end

  private

  # Nothing between here and the browser may buffer, or the tokens arrive in one
  # lump at the end and the streaming is pointless.
  def prepare_event_stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
  end

  # A client that has navigated away closes the socket mid-write; that is an
  # ordinary end to a stream, not an error worth reporting.
  def send_event(name, payload)
    response.stream.write("event: #{name}\ndata: #{payload.to_json}\n\n")
  rescue ActionController::Live::ClientDisconnected, IOError
    raise Stop
  end
end
