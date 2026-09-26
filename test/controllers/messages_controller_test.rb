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

  # #create saves the question and hands back an empty bubble; the reply
  # arrives over the stream, so nothing waits on the model here.
  test "posting a message saves it without calling the LLM" do
    ask("What does 猫 mean?")

    assert_response :success
    assert_not_requested :post, stream_url
    assert_equal "What does 猫 mean?", conversations(:lesson).messages.order(:created_at).last.content
  end

  test "streaming sends the reply and saves it" do
    stub_llm_stream("猫 (neko) ", "means cat.")
    ask("What does 猫 mean?")

    get conversation_reply_path(conversations(:lesson))

    assert_response :success
    assert_match "event: chunk", response.body
    assert_match "event: done", response.body
    assert_equal "猫 (neko) means cat.", conversations(:lesson).messages.order(:created_at).last.content
  end

  # The chunks used to be plain text, so a student watched raw markdown scroll
  # past -- asterisks, pipes, bracketed readings -- and then saw it rewritten.
  test "streamed chunks arrive already rendered" do
    stub_llm_stream("| 語 | 意味 |\n|---|---|\n| 猫[ねこ] | cat |")
    ask("show me a table")

    get conversation_reply_path(conversations(:lesson))

    html = JSON.parse(response.body[/event: chunk\ndata: (.+)/, 1])["html"]

    assert_match(/<table/, html)
    assert_match(%r{<ruby>猫<rt>ねこ</rt></ruby>}, html)
  end

  # Replaying the URL must not spend a second generation on a question that has
  # already been answered.
  test "streaming does nothing when no reply is owed" do
    stub_llm_stream("hello")

    get conversation_reply_path(conversations(:lesson))

    assert_response :no_content
    assert_not_requested :post, stream_url
  end

  test "streaming refuses another user's conversation" do
    get conversation_reply_path(conversations(:other_users_lesson))

    assert_response :not_found
  end

  # The user's message is saved before the call. A failure used to raise, so
  # they watched their message land and then got an error page.
  test "a failed reply keeps the message and says so" do
    stub_llm_stream_failure

    assert_difference -> { conversations(:lesson).messages.where(role: "user").count }, 1 do
      ask("does this survive?")
    end

    get conversation_reply_path(conversations(:lesson))

    assert_match "event: failed", response.body
    assert_equal "does this survive?", conversations(:lesson).messages.order(:created_at).last.content
  end

  # The notice said "try sending it again" whatever went wrong -- and sending
  # it again saved a second copy of the question. It now says why, and offers
  # to fetch the reply to the question already saved.
  test "a failed reply says why, and offers to try again" do
    stub_request(:post, stream_url).to_return(status: 503, body: { error: { message: "high demand" } }.to_json)
    ask("are you busy?")

    get conversation_reply_path(conversations(:lesson))

    html = JSON.parse(response.body[/^event: failed\ndata: (.*)$/, 1])["html"]
    assert_includes html, ERB::Util.html_escape(I18n.t("failures.overloaded"))
    assert_includes html, I18n.t("failures.try_again")
    assert_includes html, "reply-stream#retry"
  end

  # Trying again is the same GET the page made: it answers the saved question
  # rather than needing it sent twice.
  test "trying again answers the question already saved" do
    stub_request(:post, stream_url).to_return(status: 503, body: { error: { message: "high demand" } }.to_json)
    ask("second time lucky?")
    get conversation_reply_path(conversations(:lesson))

    stub_llm_stream("Yes!")
    assert_no_difference -> { conversations(:lesson).messages.where(role: "user").count } do
      get conversation_reply_path(conversations(:lesson))
    end

    assert_match "event: done", response.body
    assert_equal "Yes!", conversations(:lesson).messages.order(:created_at).last.content
  end

  # Pera's replies were not logged at all, so a reply of just "Hello" to "How
  # does this app work?" could not be told apart from one cut short. One line
  # per reply now says how long it was and why Gemini stopped.
  test "every reply is logged with its length and why it ended" do
    stub_llm_stream("Hello")
    ask("How does this app work?")

    log = capture_log { get conversation_reply_path(conversations(:lesson)) }

    assert_match(/Pera reply for conversation \d+: 5 characters in \d+ms, finished: \S+/, log)
  end

  test "a reply that fails is logged as failed" do
    stub_request(:post, stream_url).to_return(status: 503, body: { error: { message: "high demand" } }.to_json)
    ask("hello?")

    log = capture_log { get conversation_reply_path(conversations(:lesson)) }

    assert_match(/Pera reply for conversation \d+: failed in \d+ms/, log)
  end

  # --- naming the chat --------------------------------------------------------

  # Named from the message itself, the moment it is sent: the page's title is
  # in the same response, not waiting on the reply.
  test "the first message names the chat" do
    conversation = users(:learner).conversations.create!

    ask("How do I count flat things?", conversation)

    assert_equal "How do I count flat things?", conversation.reload.title
    assert_includes response.body, "How do I count flat things?"
  end

  # Naming used to be a second model call, made after the first reply and
  # before it was marked finished -- one more request out of the free tier,
  # and a first reply held up until it came back.
  test "the first reply makes no second request to name the chat" do
    conversation = users(:learner).conversations.create!
    stub_llm_stream("Like this.")
    ask("How do I count flat things?", conversation)

    get conversation_reply_path(conversation)

    assert_match "event: done", response.body
    assert_requested :post, stream_url, times: 1
    assert_not_requested :post, llm_url
  end

  # One message, one request: the notice asks the learner to send again rather
  # than the app retrying on its own and spending the free tier's quota.
  test "a failed reply is sent once, not retried" do
    stub_llm_stream_failure
    ask("just once")

    get conversation_reply_path(conversations(:lesson))

    assert_requested :post, stream_url, times: 1
  end

  # A notice persisted as a message would be replayed to the model next turn.
  test "the failure notice is not stored as a message" do
    stub_llm_stream_failure
    ask("hi")

    assert_no_difference -> { conversations(:lesson).messages.where(role: "assistant").count } do
      get conversation_reply_path(conversations(:lesson))
    end
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
    stub_llm_stream("ok")
    conversation = conversations(:lesson)
    (PeraReply::MAX_HISTORY_MESSAGES + 10).times do |i|
      conversation.messages.create!(role: "user", content: "filler #{i}")
    end

    ask("newest", conversation)
    get conversation_reply_path(conversation)

    assert_requested :post, stream_url do |request|
      request.body.scan(/filler /).size <= PeraReply::MAX_HISTORY_MESSAGES
    end
  end

  # The introduction is asked for once. The model cannot judge "the first time"
  # for itself: it sees the newest 30 messages, so deep into a lesson the
  # opening greeting has scrolled out and it would be told to introduce herself
  # all over again.
  test "asks Pera to introduce herself only before she has spoken" do
    stub_llm_stream("ok")
    # A first exchange also names the conversation, which is a second call.
    stub_llm_success("A first hello")
    fresh = users(:learner).conversations.create!

    ask("はじめまして", fresh)
    get conversation_reply_path(fresh)

    assert_requested :post, stream_url do |request|
      request.body.include?("Introduce")
    end
  end

  test "does not ask again once Pera has replied" do
    stub_llm_stream("ok")
    conversation = conversations(:lesson)

    ask("ねこがすきです", conversation)
    get conversation_reply_path(conversation)

    assert_requested :post, stream_url do |request|
      !request.body.include?("Introduce")
    end
  end

  # The history is replayed and then #ask sends the same message again, so the
  # model was shown every new message twice.
  test "the message being answered is sent once" do
    stub_llm_stream("ok")
    ask("uniquephrase")

    get conversation_reply_path(conversations(:lesson))

    assert_requested :post, stream_url do |request|
      request.body.scan("uniquephrase").size == 1
    end
  end

  private

  # Follows LlmChat, so switching provider cannot silently leave these stubs
  # pointing at an endpoint nothing calls.
  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  # Replies stream, so they go to a different endpoint than the one the
  # non-streaming features use, and come back as server-sent events.
  def stream_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:streamGenerateContent}
  end

  def stub_llm_stream(*chunks)
    body = chunks.map do |text|
      "data: #{{ 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => text }] } }] }.to_json}\n\n"
    end.join

    stub_request(:post, stream_url)
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: body)
  end

  def stub_llm_stream_failure
    stub_request(:post, stream_url).to_timeout
  end

  def capture_log
    output = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(output)
    yield
    output.string
  ensure
    Rails.logger = original
  end

  # What #create leaves behind: a saved question waiting for #stream.
  def ask(content, conversation = conversations(:lesson))
    post conversation_messages_path(conversation), params: { message: { content: content } }, as: :turbo_stream
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
