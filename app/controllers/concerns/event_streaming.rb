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

  # Live runs every action here on a thread of its own, before_actions
  # included -- and Devise says "not signed in" with throw :warden, which only
  # Warden's middleware, on the request's own thread, is there to catch.
  # Uncaught, a signed-out visitor to a chat got a 500 rather than the sign-in
  # page. So the throw is caught here and answered as the middleware would
  # have answered it: by Devise's failure app, which redirects a page to
  # sign-in with its usual notice and refuses anything else.
  #
  # Tests never showed it: Rails runs Live actions inline under test. See
  # test/integration/signed_out_streaming_test.rb.
  def authenticate_user!(*)
    options = catch(:warden) { return super }
    respond_as_warden_would(options)
  end

  def respond_as_warden_would(options)
    request.env["warden.options"] = { scope: :user, attempted_path: request.fullpath }
                                    .merge(options.is_a?(Hash) ? options : {})
    status, headers, body = Devise.warden_config.failure_app.call(request.env).to_a

    self.status = status
    headers.each { |name, value| response.headers[name] = value }
    self.response_body = body
  end

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
