require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Rate limits are counted in Rails.cache, which persists between tests in the
  # same process -- one test's requests would otherwise spend another's budget.
  setup do
    Rails.cache.clear
    sign_in users(:learner)
  end

  
  test "requires authentication" do
    sign_out users(:learner)
    post conversation_messages_path(conversations(:lesson)), params: { message: { content: "hi" } }

    assert_redirected_to new_user_session_path
  end

  # This was a bare Conversation.find -- the only unscoped lookup in the app --
  # so any signed-in user could post into someone else's chat and have Pera
  # answer there.
  test "refuses to post into another user's conversation" do
    theirs = conversations(:other_users_lesson)

    assert_no_difference -> { theirs.messages.count } do
      post conversation_messages_path(theirs), params: { message: { content: "hi" } }
    end

    assert_response :not_found
  end

  test "saves the message and Pera's reply" do
    stub_llm_success("猫 (neko) means cat.")

    post conversation_messages_path(conversations(:lesson)),
         params: { message: { content: "What does 猫 mean?" } }, as: :turbo_stream

    assert_response :success
    assert_equal "猫 (neko) means cat.", conversations(:lesson).messages.order(:created_at).last.content
  end

  # The user's message is saved before the call. A failure used to raise, so
  # they watched their message land and then got an error page.
  test "a failed reply keeps the message and says so" do
    stub_llm_failure

    assert_difference -> { conversations(:lesson).messages.where(role: "user").count }, 1 do
      post conversation_messages_path(conversations(:lesson)),
           params: { message: { content: "does this survive?" } }, as: :turbo_stream
    end

    assert_response :success
    assert_match(/couldn't reply/i, response.body)
    assert_match "does this survive?", response.body
  end

  # A notice persisted as a message would be replayed to the model next turn.
  test "the failure notice is not stored as a message" do
    stub_llm_failure

    post conversation_messages_path(conversations(:lesson)),
         params: { message: { content: "hi" } }, as: :turbo_stream

    assert_equal 0, conversations(:lesson).messages.where(role: "assistant")
                                          .where("content ILIKE ?", "%couldn't reply%").count
  end

  test "an empty message is rejected without calling the LLM" do
    post conversation_messages_path(conversations(:lesson)),
         params: { message: { content: "  " } }, as: :turbo_stream

    assert_not_requested :post, llm_url
  end

  test "an over-long message is rejected without calling the LLM" do
    post conversation_messages_path(conversations(:lesson)),
         params: { message: { content: "あ" * (Message::MAX_USER_CONTENT_LENGTH + 1) } }, as: :turbo_stream

    assert_not_requested :post, llm_url
    assert_equal 0, conversations(:lesson).messages.where(role: "user")
                                          .where("length(content) > ?", Message::MAX_USER_CONTENT_LENGTH).count
  end

  # The bill, not the database, is what this protects: every message is a
  # request, and nothing else stops a script from making them in a loop.
  test "messages are rate limited per account" do
    stub_llm_success("ok")

    16.times do
      post conversation_messages_path(conversations(:lesson)),
           params: { message: { content: "hi" } }, as: :turbo_stream
    end

    assert_response :too_many_requests
    assert_match(/moment/i, response.body)
  end

  test "a rate limited message costs no LLM call and stores nothing" do
    stub_llm_success("ok")
    15.times do
      post conversation_messages_path(conversations(:lesson)),
           params: { message: { content: "hi" } }, as: :turbo_stream
    end
    WebMock.reset_executed_requests!

    assert_no_difference -> { conversations(:lesson).messages.count } do
      post conversation_messages_path(conversations(:lesson)),
           params: { message: { content: "one too many" } }, as: :turbo_stream
    end

    assert_not_requested :post, llm_url
  end

  # Every reply replayed the whole conversation, so a long chat re-sent (and
  # re-paid for) everything said in it.
  test "only the most recent messages are replayed to the model" do
    stub_llm_success("ok")
    conversation = conversations(:lesson)
    (MessagesController::MAX_HISTORY_MESSAGES + 10).times do |i|
      conversation.messages.create!(role: "user", content: "filler #{i}")
    end

    post conversation_messages_path(conversation), params: { message: { content: "newest" } }, as: :turbo_stream

    assert_requested :post, llm_url do |request|
      request.body.scan(/filler /).size <= MessagesController::MAX_HISTORY_MESSAGES
    end
  end

  # The history is replayed and then #ask sends the same message again, so the
  # model was shown every new message twice.
  test "the message being answered is sent once" do
    stub_llm_success("ok")

    post conversation_messages_path(conversations(:lesson)),
         params: { message: { content: "uniquephrase" } }, as: :turbo_stream

    assert_requested :post, llm_url do |request|
      request.body.scan("uniquephrase").size == 1
    end
  end

  private

  # Follows LlmChat, so switching provider cannot silently leave these stubs
  # pointing at an endpoint nothing calls.
  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  def stub_llm_success(text)
    stub_request(:post, llm_url)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { "candidates" => [{ "content" => { "parts" => [{ "text" => text }] } }] }.to_json)
  end

  def stub_llm_failure
    stub_request(:post, llm_url).to_timeout
  end
end
