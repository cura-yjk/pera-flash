require "test_helper"

# Chat content is markdown *and* Japanese: rendered, sanitized, then annotated.
# Both halves matter -- the sanitize step because the output is inserted as
# HTML, the annotation because the chat is where most Japanese is read.
class ChatRenderingTest < ActionView::TestCase
  include ApplicationHelper
  include FuriganaHelper

  def current_user = nil

  test "a script tag cannot execute" do
    assert_no_match(/<script/, rendered("<script>alert(1)</script>"))
  end

  test "an event handler is stripped" do
    assert_no_match(/onerror/, rendered(%q{<img src=x onerror="alert(1)">}))
  end

  test "a javascript: link loses its href" do
    assert_no_match(/javascript:/, rendered("[click](javascript:alert(1))"))
  end

  test "an ordinary link survives" do
    assert_match %r{href="https://example.com"}, rendered("[docs](https://example.com)")
  end

  # Rails' default allowlist drops <table>, and Pera's vocabulary breakdown is
  # a table -- the default would delete the most useful part of every reply.
  test "a markdown table survives" do
    html = rendered("| 語 | 意味 |\n|---|---|\n| 猫 | cat |")

    assert_match(/<table/, html)
    assert_match(/<td>cat<\/td>/, html)
  end

  # Pera often writes the breakdown table on the line straight after its
  # label, and Kramdown only starts a table after a blank line -- so the table
  # came out as a paragraph of raw pipes. The shape here is a real reply's.
  test "a table straight after a line of text still renders, inside its list item" do
    html = rendered(<<~MD)
      * **Breakdown:**
        | Japanese Word | English Meaning |
        | :--- | :--- |
        | が | subject marker particle |
      * **Why:**
        * が marks what you like.
    MD

    assert_match(/<li>.*<table/m, html)
    assert_match(/<td>subject marker particle<\/td>/, html)
    assert_no_match(/\| Japanese Word/, html)
  end

  test "pipes in an ordinary sentence are left alone" do
    assert_no_match(/<table/, rendered("Choose one:\n| this | or that |"))
  end

  test "a table inside a code block stays code" do
    assert_no_match(/<table/, rendered("```\nsome text\n| a | b |\n| --- | --- |\n```"))
  end

  test "readings in a reply render as ruby" do
    assert_match(/<ruby>猫<rt>ねこ<\/rt><\/ruby>/, rendered("猫[ねこ]が 好[す]きです"))
  end

  test "readings inside a table cell render too" do
    assert_match(/<ruby>猫<rt>ねこ<\/rt><\/ruby>/, rendered("| 語 |\n|---|\n| 猫[ねこ] |"))
  end

  test "readings can be switched off" do
    html = with_furigana_html(render_markdown("猫[ねこ]です"), show: false)

    assert_match "猫です", html
    assert_no_match(/<ruby>/, html)
  end

  # The annotation pass runs over rendered HTML, so it must not rewrite
  # anything inside a tag and turn an attribute into markup.
  test "an annotation inside an attribute is left alone" do
    html = rendered("[x](https://example.com/猫[ねこ])")

    assert_no_match(/<a[^>]*<ruby>/, html)
  end

  private

  def rendered(markdown)
    with_furigana_html(render_markdown(markdown), show: true).to_s
  end
end
