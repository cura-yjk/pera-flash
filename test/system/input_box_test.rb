require "application_system_test_case"

# The chat box, which is the app's main control and was the least tested part
# of it. Every one of these is browser behaviour: none of it is visible to a
# test that only reads HTML.
class InputBoxTest < ApplicationSystemTestCase
  setup do
    @conversation = conversations(:lesson)
    sign_in_as(users(:learner))
  end

  # enter_submit_controller was written with IME handling and never wired up:
  # no targets, no keydown, and a "Missing target element" error on every page
  # load. Enter did nothing.
  test "Enter sends the message" do
    stub_stream("はい。")
    visit conversation_path(@conversation)

    assert_difference -> { @conversation.messages.where(role: "user").count }, 1 do
      fill_in "message[content]", with: "エンターで送ります"
      find("#chat-input").send_keys(:enter)
      assert_text "エンターで送ります"
    end
  end

  test "Shift+Enter starts a new line instead of sending" do
    visit conversation_path(@conversation)

    assert_no_difference -> { @conversation.messages.count } do
      fill_in "message[content]", with: "一行目"
      find("#chat-input").send_keys([:shift, :enter])
      find("#chat-input").send_keys("二行目")
      sleep 0.3
    end

    assert_includes find("#chat-input").value, "\n"
  end

  test "the box grows with the message" do
    visit conversation_path(@conversation)
    start = height_of_input

    type("日本語の長い文章です。" * 20)

    assert_operator height_of_input, :>, start
  end

  test "the box stops growing rather than taking over the screen" do
    visit conversation_path(@conversation)

    type("とても長い文章です。" * 300)

    assert_operator height_of_input, :<=, 200
  end

  # maxlength stops keystrokes silently at the cap, which is baffling without
  # something on screen to explain it.
  test "the remaining characters appear near the limit" do
    visit conversation_path(@conversation)

    assert_no_selector "[data-char-count-target='counter']", visible: true

    type("あ" * (Message::MAX_USER_CONTENT_LENGTH - 20))

    assert_selector "[data-char-count-target='counter']", visible: true, text: /20/
  end

  # A second question sent mid-reply saved fine but was never answered: the
  # reply endpoint only answers the last unanswered one.
  test "the box is locked while Pera is replying" do
    stub_stream("考え中...")
    visit conversation_path(@conversation)

    fill_in "message[content]", with: "最初の質問"
    click_on "Send"

    assert_selector "#chat-input[disabled]", wait: 5
  end

  test "the box is usable again once the reply lands" do
    stub_stream("終わりました。")
    visit conversation_path(@conversation)

    fill_in "message[content]", with: "質問"
    click_on "Send"

    assert_text "終わりました。", wait: 10
    assert_no_selector "#chat-input[disabled]"
  end

  private

  # Types by setting the value and firing one input event.
  #
  # Capybara's fill_in switches to assigning the value directly for long
  # strings, which fires no input event at all -- so the box never resized and
  # the counter never updated, and the tests failed against working code. The
  # Enter tests below still type for real, where the keystrokes are the point.
  def type(text)
    page.execute_script(<<~JS, text)
      const input = document.querySelector("#chat-input");
      input.value = arguments[0];
      input.dispatchEvent(new Event("input", { bubbles: true }));
    JS
  end

  def height_of_input
    page.evaluate_script("Math.round(document.querySelector('#chat-input').getBoundingClientRect().height)")
  end

  def stub_stream(*chunks)
    body = chunks.map do |text|
      "data: #{{ 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => text }] } }] }.to_json}\n\n"
    end.join

    stub_request(:post, %r{generativelanguage\.googleapis\.com/.*streamGenerateContent})
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: body)
  end
end
