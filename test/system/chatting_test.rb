require "application_system_test_case"

# The chat, with the model stubbed at the HTTP level so the reply streams
# through the real pipeline -- SSE endpoint, Stimulus controller, server-side
# rendering of each update -- without spending a request.
class ChattingTest < ApplicationSystemTestCase
  setup do
    @user = users(:learner)
    @conversation = conversations(:lesson)
    sign_in_as(@user)
  end

  test "a reply streams in and ends up rendered" do
    stub_stream("**猫[ねこ]**が好きです。", " Nicely done!")

    visit conversation_path(@conversation)
    fill_in "message[content]", with: "ねこがすきです"
    click_on "Send"

    # Rendered as it arrives: bold is bold, and the reading is a ruby tag --
    # not raw asterisks and brackets waiting to be rewritten at the end.
    assert_selector "strong", text: "猫", wait: 10
    assert_selector "ruby rt", text: "ねこ"
    assert_text "Nicely done!"
  end

  test "a new chat suggests what to say" do
    empty = @user.conversations.create!(title: "Fresh chat")

    visit conversation_path(empty)

    assert_text "How does this app work?"
  end

  private

  # Gemini's streaming wire format: one SSE frame per chunk.
  def stub_stream(*chunks)
    body = chunks.map do |text|
      "data: #{{ 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => text }] } }] }.to_json}\n\n"
    end.join

    stub_request(:post, %r{generativelanguage\.googleapis\.com/.*streamGenerateContent})
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: body)
  end
end
