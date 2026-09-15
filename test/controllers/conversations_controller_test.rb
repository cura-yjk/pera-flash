require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Rails.cache.clear
    sign_in users(:learner)
  end

  test "requires authentication" do
    sign_out users(:learner)
    get conversation_path(conversations(:lesson))

    assert_redirected_to new_user_session_path
  end

  test "index lists the user's own conversations" do
    get conversations_path

    assert_response :success
    assert_select "a", text: conversations(:lesson).title
  end

  test "index does not leak another user's conversations" do
    get conversations_path

    assert_response :success
    assert_select "a", text: conversations(:other_users_lesson).title, count: 0
  end

  # #create leaves empty conversations behind by design, and they carry no
  # information -- a history list full of "Untitled conversation" is noise.
  test "index hides conversations with no messages" do
    get conversations_path

    assert_select "a", text: conversations(:abandoned).title, count: 0
  end

  test "index requires authentication" do
    sign_out users(:learner)
    get conversations_path

    assert_redirected_to new_user_session_path
  end

  # The generation limit is 5/minute. Declared without `only:` it applied to
  # every action in the controller, so the sixth conversation you merely opened
  # came back refused -- reading a chat costs nothing and must not be throttled.
  test "reading conversations is not throttled by the generation limit" do
    10.times { get conversation_path(conversations(:lesson)) }

    assert_response :success
  end

  # A new chat was a blank page: nothing told a beginner they could ask Pera
  # how the app works, which is the only way that help is discoverable.
  test "a new chat suggests what to say" do
    empty = current_user_conversation_with_no_messages

    get conversation_path(empty)

    assert_response :success
    assert_match(/How does this app work/, response.body)
    assert_select "form[action=?]", conversation_messages_path(empty)
  end

  test "a conversation with history shows no suggestions" do
    get conversation_path(conversations(:lesson))

    assert_no_match(/How does this app work/, response.body)
  end

  test "show refuses another user's conversation" do
    get conversation_path(conversations(:other_users_lesson))

    assert_response :not_found
  end

  # --- flashcard generation -------------------------------------------------

  test "generates cards only from what was said since the last batch" do
    stub_llm_success([{ question: "How do you say 'I like cats'?", answer: "猫が好きです (neko ga suki desu)" }])

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_response :success
    # The prompt must carry the new exchange and not the already-carded one.
    assert_requested :post, llm_url do |req|
      body = req.body.to_s
      body.include?("I like cats") && !body.include?("How do I say \"cat\" in Japanese?")
    end
  end

  # Previously this cost a full generation to discover there was nothing new.
  test "says nothing is new without calling the LLM at all" do
    conversations(:lesson).flashcards.update_all(created_at: Time.current)

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_response :success
    assert_match(/caught up/i, response.body)
    assert_not_requested :post, llm_url
  end

  test "generates from the whole conversation the first time" do
    conversations(:lesson).flashcards.destroy_all
    stub_llm_success([{ question: "What does 猫 mean?", answer: "Cat (neko)" }])

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_response :success
    assert_requested :post, llm_url do |req|
      req.body.to_s.include?("cat") && req.body.to_s.include?("I like cats")
    end
  end

  test "generate_flashcards refuses another user's conversation" do
    post generate_flashcards_conversation_path(conversations(:other_users_lesson)), as: :turbo_stream

    assert_response :not_found
  end

  # A provider outage used to 500 the whole action.
  test "says so when flashcards cannot be generated" do
    stub_request(:post, llm_url).to_timeout

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_response :success
    # Matched against the translation so it stays true in any locale, and
    # escaped because t() escapes the apostrophe on its way into the page.
    assert_match ERB::Util.html_escape(I18n.t("conversations.generation_failed.title")), response.body
  end

  test "a failed generation leaves the conversation untouched" do
    stub_request(:post, llm_url).to_timeout

    assert_no_difference -> { conversations(:lesson).flashcards.count } do
      post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream
    end
  end

  private

  def current_user_conversation_with_no_messages
    users(:learner).conversations.create!(title: "Fresh chat")
  end

  # Follows LlmChat, so switching provider cannot silently leave these stubs
  # pointing at an endpoint nothing calls.
  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  
  def stub_llm_success(cards)
    stub_request(:post, llm_url)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "candidates" => [{ "content" => { "parts" => [{ "text" => { flashcards: cards }.to_json }] } }]
      }.to_json)
  end
end
