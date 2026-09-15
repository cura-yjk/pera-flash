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
    click_and_confirm("Send", expect: "ねこがすきです")

    # Rendered as it arrives: bold is bold, and the reading is a ruby tag --
    # not raw asterisks and brackets waiting to be rewritten at the end.
    assert_selector "strong", text: "猫", wait: 10
    assert_selector "ruby rt", text: "ねこ"
    assert_text "Nicely done!"
  end

  # The input box is fixed to the bottom of the window, and the newest message
  # scrolls itself into view. Lining its bottom up with the bottom of the
  # window put it behind the input box: measured, the last 100px of text sat
  # underneath the thing you type into.
  #
  # Driven without sending a message, because the geometry is the point and a
  # click adds nothing to it.
  test "the newest message stays clear of the input box" do
    @conversation.messages.create!(role: "assistant", content: (1..30).map { |i| "これは #{i} 行目です。" }.join("\n\n"))

    visit conversation_path(@conversation)
    assert_text "30 行目"

    assert_operator clearance_below_last_message, :>=, 0,
                    "the newest text sits #{clearance_below_last_message.abs}px underneath the input box"
  end

  test "a new chat suggests what to say" do
    empty = @user.conversations.create!(title: "Fresh chat")

    visit conversation_path(empty)

    assert_text "How does this app work?"
  end

  private

  # Pixels between the bottom of the last message and the top of the docked
  # input, after scrolling to it the way the app does.
  #
  # behavior: "instant" on purpose. Bootstrap sets scroll-behavior: smooth on
  # html, so a scroll started here is still animating a moment later --
  # measuring then reads the old position, and the test passes whatever the
  # layout does. That is how my first version of this passed against the bug.
  def clearance_below_last_message
    page.evaluate_script(<<~JS)
      (function () {
        const last = document.querySelector("#messages > *:last-child");
        const dock = document.querySelector(".chat-dock");
        if (!last || !dock) return null;

        last.scrollIntoView({ block: "end", behavior: "instant" });

        return Math.round(dock.getBoundingClientRect().top - last.getBoundingClientRect().bottom);
      })()
    JS
  end

  # Gemini's streaming wire format: one SSE frame per chunk.
  def stub_stream(*chunks)
    body = chunks.map do |text|
      "data: #{{ 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => text }] } }] }.to_json}\n\n"
    end.join

    stub_request(:post, %r{generativelanguage\.googleapis\.com/.*streamGenerateContent})
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: body)
  end
end
