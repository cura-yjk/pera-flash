require "test_helper"

class ConversationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:learner) }

  test "requires authentication" do
    sign_out users(:learner)
    get conversation_path(conversations(:lesson))

    assert_redirected_to new_user_session_path
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
    assert_requested :post, LLM_URL do |req|
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
    assert_not_requested :post, LLM_URL
  end

  test "generates from the whole conversation the first time" do
    conversations(:lesson).flashcards.destroy_all
    stub_llm_success([{ question: "What does 猫 mean?", answer: "Cat (neko)" }])

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_response :success
    assert_requested :post, LLM_URL do |req|
      req.body.to_s.include?("cat") && req.body.to_s.include?("I like cats")
    end
  end

  test "generate_flashcards refuses another user's conversation" do
    post generate_flashcards_conversation_path(conversations(:other_users_lesson)), as: :turbo_stream

    assert_response :not_found
  end

  private

  LLM_URL = "https://api.openai.com/v1/chat/completions".freeze

  def stub_llm_success(cards)
    stub_request(:post, LLM_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        "choices" => [{ "message" => { "content" => { flashcards: cards }.to_json } }]
      }.to_json)
  end
end
