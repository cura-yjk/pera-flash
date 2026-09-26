require "test_helper"

# A signed-out visitor to either streaming controller got a 500, not the
# sign-in page. ActionController::Live runs every action of a controller that
# includes it -- before_actions too -- on a thread of its own, and Devise's
# authenticate_user! says "not signed in" with throw :warden, which only
# Warden's middleware, back on the request's thread, is there to catch.
#
# The controller tests never saw it: under test, Rails runs Live actions
# inline on the request's thread (actionpack's test_case.rb), where the throw
# is caught as usual. So these requests put the real thread back.
class SignedOutStreamingTest < ActionDispatch::IntegrationTest
  test "a chat page sends a signed-out visitor to sign in" do
    with_live_threads { get conversation_path(conversations(:lesson)) }

    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_match I18n.t("devise.failure.unauthenticated"), response.body
  end

  test "the chat history sends a signed-out visitor to sign in" do
    with_live_threads { get conversations_path }

    assert_redirected_to new_user_session_path
  end

  # The refusal leaves the session usable: signing in lands where every
  # sign-in does (ApplicationController#after_sign_in_path_for).
  test "signing in afterwards works as it does from any page" do
    with_live_threads { get conversation_path(conversations(:lesson)) }

    post user_session_path, params: { user: { email: users(:learner).email, password: "password123" } }

    assert_redirected_to dashboard_path
  end

  test "Pera's reply stream refuses a signed-out request without crashing" do
    with_live_threads do
      get conversation_reply_path(conversations(:lesson)), headers: { "Accept" => "text/event-stream" }
    end

    assert_includes [302, 401], response.status
  end

  test "card generation refuses a signed-out request without crashing" do
    with_live_threads do
      post generate_flashcards_conversation_path(conversations(:lesson)),
           headers: { "Accept" => "text/event-stream, text/vnd.turbo-stream.html" }
    end

    assert_includes [302, 401], response.status
  end

  private

  def with_live_threads
    live = ActionController::Live
    live.alias_method :inline_controller_thread, :new_controller_thread
    live.alias_method :new_controller_thread, :original_new_controller_thread
    yield
  ensure
    live.alias_method :new_controller_thread, :inline_controller_thread
  end
end
