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
    type_into("ねこがすきです")
    click_and_confirm("Send", expect: "ねこがすきです")

    # Rendered as it arrives: bold is bold, and the reading is a ruby tag --
    # not raw asterisks and brackets waiting to be rewritten at the end.
    assert_selector "strong", text: "猫", wait: 10
    assert_selector "ruby rt", text: "ねこ"
    assert_text "Nicely done!"
  end

  # Try again fetches the reply to the question already saved: the old advice
  # was to send it again, which saved it twice.
  test "a failed reply says why, and Try again fetches it without resending" do
    stub_request(:post, %r{generativelanguage\.googleapis\.com/.*streamGenerateContent})
      .to_return(status: 503, body: { error: { message: "high demand" } }.to_json).then
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" },
                 body: "data: #{{ 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => 'Here I am!' }] } }] }.to_json}\n\n")

    visit conversation_path(@conversation)
    type_into("are you there?")
    click_and_confirm("Send", expect: "busy right now")

    assert_no_difference -> { @conversation.messages.where(role: "user").count } do
      click_and_confirm("Try again", expect: "Here I am!")
    end
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

  # Sending moves the question up under the navbar once, and then the page
  # holds still while the reply grows below it. It used to follow the reply
  # down, which kept the text being written against the input box and moved
  # the page under the reader with every chunk. The reply here is several
  # windows long, so a page that still chased it would end up far from the
  # question.
  test "the question moves to the top and stays there while the reply grows" do
    stub_stream(*(1..30).map { |i| "これは #{i} 行目です。\n\n" })

    visit conversation_path(@conversation)
    type_into("ながい こたえを ください")
    click_and_confirm("Send", expect: "ながい こたえを ください")

    assert_text "30 行目", wait: 15
    assert_no_selector "[data-controller~='reply-stream']", wait: 15

    page.document.synchronize(5) do
      gap = gap_between_navbar_and_question
      raise Capybara::ExpectationNotMet, "the question sits #{gap}px below the navbar" unless gap.between?(8, 24)
    end
  end

  # The page holds still while the reply grows, so a long one runs on under the
  # input box with nothing to say it is still coming. Long enough here to be
  # revealing for a few seconds, which is the window the button lives in.
  test "a reply running on out of sight offers a way down to it" do
    stub_stream(*(1..80).map { |i| "これは #{i} 行目です。\n\n" })

    visit conversation_path(@conversation)
    type_into("ながい こたえを ください")
    click_and_confirm("Send", expect: "ながい こたえを ください")

    start = page.evaluate_script("window.scrollY")
    click_button "More below", wait: 10

    # Any distance down, not a fixed amount: the button appears as soon as the
    # newest line slips out of sight, so the scroll it asks for can be small.
    # A 100px threshold passed in Chrome and failed in Firefox, which clicked
    # when the line was 76px out.
    page.document.synchronize(5) do
      raise Capybara::ExpectationNotMet, "clicking did not scroll down" unless page.evaluate_script("window.scrollY") > start
    end

    assert_text "80 行目", wait: 15
    assert_no_button "More below", wait: 15
  end

  # The reply streamed into a box styled white-space: pre-wrap, left over from
  # when it streamed as plain text. Once it streamed as HTML, the line breaks
  # between tags showed as blank lines: measured, a four-block reply stood
  # 432px tall while writing and dropped to 184px when it finished.
  test "the reply does not shrink when it finishes" do
    stub_stream("初めまして！\n\n", "I am ペラ.\n\n", "- one\n- two\n\n", "Let us practise.")

    visit conversation_path(@conversation)
    page.execute_script(<<~JS)
      window.tallestWhileWriting = 0;
      new MutationObserver(() => {
        const text = document.querySelector("[data-reply-stream-target=text]");
        if (text) window.tallestWhileWriting = Math.max(window.tallestWhileWriting, text.getBoundingClientRect().height);
      }).observe(document.getElementById("messages"), { childList: true, subtree: true });
    JS
    type_into("はじめまして")
    click_and_confirm("Send", expect: "はじめまして")

    assert_text "Let us practise.", wait: 15
    assert_no_selector "[data-controller~='reply-stream']", wait: 15

    finished = page.evaluate_script(<<~JS)
      (function () {
        const replies = document.querySelectorAll("#messages .assistant-message");
        const reply = replies[replies.length - 1];
        const style = getComputedStyle(reply);
        return reply.getBoundingClientRect().height - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom);
      })()
    JS
    tallest = page.evaluate_script("window.tallestWhileWriting")

    assert_operator tallest, :<=, finished, "the reply stood #{tallest.round}px while writing and #{finished.round}px when finished"
  end

  # Renamed in place: the pencil swaps the title for a box, and saving swaps it
  # back, without leaving the chat.
  test "a chat can be renamed from its title" do
    visit conversation_path(@conversation)

    open_rename
    type_into("Cats, and liking them", field: "#conversation_name")
    click_and_confirm("Save", expect: "Cats, and liking them")

    assert_selector "h2", text: "Cats, and liking them"
    assert_no_field "Chat name"

    visit conversation_path(@conversation)
    assert_selector "h2", text: "Cats, and liking them"
  end

  test "cancelling a rename keeps the name" do
    visit conversation_path(@conversation)

    open_rename
    type_into("Something else", field: "#conversation_name")
    click_link "Cancel"

    assert_selector "h2", text: "Talking about cats", wait: 10
    assert_equal "Talking about cats", @conversation.reload.title
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

  # The pencil, with the same fallback click_and_confirm gives a button: the
  # form has no text of its own to wait for, so this waits for its field.
  def open_rename
    pencil = find_link("Rename chat")
    pencil.click
    return if page.has_field?("Chat name", wait: 3)

    pencil.evaluate_script("this.click()")
    assert_field "Chat name", wait: 10
  end

  # From the bottom of the fixed navbar to the top of the question just sent.
  # Retried by the caller rather than measured once: the scroll up to the
  # question is smooth, and reading mid-animation gives a number that is
  # neither where it started nor where it ends.
  def gap_between_navbar_and_question
    page.evaluate_script(<<~JS)
      (function () {
        const questions = document.querySelectorAll("#messages .user-message");
        const question = questions[questions.length - 1];
        const navbar = document.querySelector(".nav-bar");

        return Math.round(question.getBoundingClientRect().top - navbar.getBoundingClientRect().bottom);
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
