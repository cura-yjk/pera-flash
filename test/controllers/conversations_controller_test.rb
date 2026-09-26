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

  # --- renaming -----------------------------------------------------------------

  test "the rename form sits in the title's frame" do
    get edit_conversation_path(conversations(:lesson))

    assert_response :success
    assert_select "turbo-frame#conversation_title input[name='conversation[title]'][value=?]", "Talking about cats"
  end

  test "renaming a chat saves the new name" do
    patch conversation_path(conversations(:lesson)), params: { conversation: { title: "Cats, and liking them" } }

    assert_redirected_to conversation_path(conversations(:lesson))
    assert_equal "Cats, and liking them", conversations(:lesson).reload.title
  end

  test "a blank name is refused and the old one kept" do
    patch conversation_path(conversations(:lesson)), params: { conversation: { title: " " } }

    assert_response :unprocessable_entity
    assert_equal "Talking about cats", conversations(:lesson).reload.title
  end

  test "another user's chat cannot be renamed" do
    patch conversation_path(conversations(:other_users_lesson)), params: { conversation: { title: "Mine now" } }

    assert_response :not_found
    assert_not_equal "Mine now", conversations(:other_users_lesson).reload.title
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
  # The old assertions only checked what was sent, never what came back -- so
  # they passed while every generated card arrived blank. ruby_llm 2.0 returns
  # a schema response as a String, and String#[] with a key is a substring
  # match: content["flashcards"] gave back the word "flashcards", Array() made
  # one element of it, and "flashcards"["question"] is nil.
  test "the cards that come back carry the question and answer" do
    stub_llm_success([{ question: "What does 猫 mean?", answer: "Cat (neko)" }])

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_response :success
    assert_includes response.body, "What does 猫 mean?"
    assert_includes response.body, "Cat (neko)"
  end

  test "every card the model returns is offered" do
    stub_llm_success([
      { question: "What does 猫 mean?", answer: "Cat" },
      { question: "What does 犬 mean?", answer: "Dog" }
    ])

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_includes response.body, "What does 猫 mean?"
    assert_includes response.body, "What does 犬 mean?"
  end

  # A generation shows nothing until the whole list is written, so every extra
  # card is extra waiting. The schema and prompt both ask for at most ten; this
  # is the trim for a model that returns more anyway.
  test "offers at most the card limit even when the model returns more" do
    limit = FlashcardsSchema::MAX_CARDS
    stub_llm_success((1..limit + 2).map { |i| { question: "Question number #{i}?", answer: "Answer #{i}" } })

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_includes response.body, "Question number #{limit}?"
    assert_not_includes response.body, "Question number #{limit + 1}?"
  end

  test "generation is told how many cards it may return" do
    stub_llm_success([])

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_requested :post, llm_url do |request|
      body = JSON.parse(request.body)
      body.to_s.include?("at most #{FlashcardsSchema::MAX_CARDS} cards") &&
        body.dig("generationConfig", "responseJsonSchema", "properties", "flashcards", "maxItems") == FlashcardsSchema::MAX_CARDS
    end
  end

  # "Slow sometimes" could not be followed up: nothing recorded how long a
  # generation took or how much it was given.
  test "each generation logs how long it took and what went in" do
    stub_llm_success([{ question: "What does 猫 mean?", answer: "Cat" }])

    log = capture_log do
      post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream
    end

    assert_match(/Flashcard generation for conversation \d+: 1 cards in \d+ms from \d+ messages \(\d+ characters\)/, log)
  end

  # Generation reads a long stretch of chat and Gemini can take a while to
  # start; the 30s every other call waits threw away answers it was about to
  # give. Both ways of generating ask for the longer wait.
  test "generation waits longer for Gemini than a reply does" do
    timeouts = []
    original = LlmChat.method(:with_chat)
    # Minitest 6 has no #stub; swapped by hand and put back.
    LlmChat.define_singleton_method(:with_chat) do |timeout: nil, &_block|
      timeouts << timeout
      raise RubyLLM::Error.new(nil, "stop here")
    end

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream
    post_for_stream

    assert_equal [FlashcardGeneration::TIMEOUT] * 2, timeouts
  ensure
    LlmChat.define_singleton_method(:with_chat, original)
  end

  # --- streamed generation ------------------------------------------------------

  test "a streamed generation sends each card as its own event" do
    stub_llm_stream([{ question: "What does 猫 mean?", answer: "Cat" }, { question: "What does 犬 mean?", answer: "Dog" }])

    post_for_stream

    assert_equal "text/event-stream", response.media_type
    assert_equal %w[open card card done], events.map(&:first)
    assert_includes events[1].last["html"], "What does 猫 mean?"
    assert_includes events[2].last["html"], "conversation[flashcards][1][question]"
    assert_equal 2, events.last.last["count"]
  end

  # The same trim as the whole response: a streamed list stops at the limit.
  test "a streamed generation stops at the card limit" do
    limit = FlashcardsSchema::MAX_CARDS
    stub_llm_stream((1..limit + 2).map { |i| { question: "Question number #{i}?", answer: "Answer #{i}" } })

    post_for_stream

    assert_equal limit, events.count { |name, _| name == "card" }
    assert_equal limit, events.last.last["count"]
  end

  # Only a generation streams. Everything else comes back as the turbo_stream
  # it always was, and the browser hands it to Turbo.
  test "nothing new is still an ordinary turbo_stream when streaming was asked for" do
    conversations(:lesson).flashcards.update_all(created_at: Time.current)

    post_for_stream

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(/caught up/i, response.body)
    assert_not_requested :post, llm_stream_url
  end

  # The rate limit's handler answers with respond_to, and a streaming request
  # lists text/event-stream first. It has to fall through to turbo_stream
  # rather than finding no format and answering 406.
  test "a rate-limited streaming request gets the usual notice" do
    conversations(:lesson).flashcards.update_all(created_at: Time.current)

    6.times { post_for_stream }

    assert_response :too_many_requests
    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  test "a streamed generation that fails says so" do
    stub_request(:post, llm_stream_url).to_return(status: 500, body: "{}")

    post_for_stream

    assert_equal %w[open failed], events.map(&:first)
    assert_includes events.last.last["html"], "make flashcards just now"
  end

  # Generation only ever sees a transcript, and a transcript of Japanese
  # practice contains almost nothing to infer an explanation language from --
  # so it is told outright rather than left to guess.
  test "generation is told the language the cards should explain in" do
    stub_llm_success([])

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_requested :post, llm_url do |request|
      request.body.to_s.include?("Explain in English")
    end
  end

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
  # One tap, one request. ruby_llm retried a failed request three more times
  # on its own, so a single tap on a bad Gemini day spent four of the free
  # tier's few daily requests and kept the learner waiting two minutes. The
  # notice asks them to try again instead, which is their call to make.
  test "a failed generation is sent once, not retried" do
    stub_request(:post, llm_url).to_return(status: 503, body: { error: { message: "high demand" } }.to_json)

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_requested :post, llm_url, times: 1
    assert_match ERB::Util.html_escape(I18n.t("conversations.generation_failed.title")), response.body
  end

  test "a generation that times out is sent once, not retried" do
    stub_request(:post, llm_url).to_timeout

    post generate_flashcards_conversation_path(conversations(:lesson)), as: :turbo_stream

    assert_requested :post, llm_url, times: 1
  end

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

  # --- create ---------------------------------------------------------------
  #
  # Starting a chat was the one part of the flow with no test: every other test
  # here begins from a conversation already in the fixtures.

  test "create requires authentication" do
    sign_out users(:learner)

    post conversations_path

    assert_redirected_to new_user_session_path
  end

  test "starts a conversation and goes straight to it" do
    post conversations_path

    conversation = users(:learner).conversations.order(:id).last

    assert_redirected_to conversation_path(conversation)
    assert_equal "Let's chat!", conversation.title, "the real title is written once there is a message to name it after"
  end

  # #create clears these out first, so pressing "new chat" repeatedly leaves
  # one empty conversation rather than a pile of them.
  test "clears out the empty conversations left behind before it" do
    abandoned = conversations(:abandoned)

    post conversations_path

    assert_not Conversation.exists?(abandoned.id)
  end

  test "pressing it twice does not pile up empty conversations" do
    post conversations_path
    post conversations_path

    assert_equal 1, users(:learner).conversations.empty.count
  end

  test "leaves a conversation that has been used alone" do
    post conversations_path

    assert Conversation.exists?(conversations(:lesson).id)
  end

  test "does not clear out another learner's empty conversations" do
    stranger_conversation = conversations(:other_users_lesson)

    post conversations_path

    assert Conversation.exists?(stranger_conversation.id),
           "destroy_all is scoped to current_user, and must stay that way"
  end

  # `resources :conversations` routes GET /conversations/new, but there is no
  # new action and no template: a chat is started by posting, from the button.
  test "there is no new-conversation page" do
    get new_conversation_path

    assert_response :not_found
  end

  private

  def post_for_stream
    post generate_flashcards_conversation_path(conversations(:lesson)),
         headers: { "Accept" => "text/event-stream, text/vnd.turbo-stream.html" }
  end

  # [name, data] for each server-sent event in the response.
  def events
    response.body.split("\n\n").map do |frame|
      [frame[/^event: (.*)$/, 1], JSON.parse(frame[/^data: (.*)$/, 1])]
    end
  end

  def llm_stream_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:streamGenerateContent}
  end

  # The cards' JSON as Gemini streams it: in pieces that split cards apart.
  def stub_llm_stream(cards)
    json = { flashcards: cards }.to_json
    body = json.chars.each_slice(17).map do |piece|
      "data: #{{ 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => piece.join }] } }] }.to_json}\n\n"
    end.join

    stub_request(:post, llm_stream_url)
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: body)
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
