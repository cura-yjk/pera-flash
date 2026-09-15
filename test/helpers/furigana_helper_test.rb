require "test_helper"

class FuriganaHelperTest < ActionView::TestCase
  include FuriganaHelper

  test "wraps a kanji and its reading in ruby tags" do
    assert_equal "<ruby>猫<rt>ねこ</rt></ruby>", with_furigana("猫[ねこ]")
  end

  test "annotates each kanji run separately and leaves kana alone" do
    assert_equal "<ruby>猫<rt>ねこ</rt></ruby>が<ruby>好<rt>す</rt></ruby>きです",
                 with_furigana("猫[ねこ]が好[す]きです")
  end

  test "keeps okurigana outside the reading" do
    assert_equal "<ruby>食<rt>た</rt></ruby>べる", with_furigana("食[た]べる")
  end

  test "treats a compound as one run" do
    assert_equal "<ruby>学生<rt>がくせい</rt></ruby>", with_furigana("学生[がくせい]")
  end

  # Every card made before furigana existed has no brackets.
  test "leaves unannotated text untouched" do
    assert_equal "ねこが すき です。", with_furigana("ねこが すき です。")
  end

  test "strips readings when they are turned off" do
    assert_equal "猫が好きです", with_furigana("猫[ねこ]が好[す]きです", show: false)
  end

  # Flashcards are user-editable, so the text is untrusted. Escaping has to
  # happen before the ruby tags go in, or this is an injection hole.
  test "escapes HTML in the card text" do
    rendered = with_furigana("<script>alert(1)</script>猫[ねこ]")

    assert_includes rendered, "&lt;script&gt;"
    assert_not_includes rendered, "<script>"
    assert_includes rendered, "<ruby>猫<rt>ねこ</rt></ruby>"
  end

  test "escapes HTML when readings are turned off too" do
    assert_not_includes with_furigana("<b>x</b>猫[ねこ]", show: false), "<b>"
  end

  # A bracket that isn't a reading is just text.
  test "ignores brackets that do not follow kanji" do
    assert_equal "see [note]", with_furigana("see [note]")
  end

  test "handles nil" do
    assert_equal "", with_furigana(nil)
  end

  # Both branches have to come back marked safe. gsub on a SafeBuffer returns a
  # plain String, so the hidden branch was escaped a second time by the view --
  # a card reading "It's polite" reached the screen as "It&#39;s polite", and
  # only once readings were switched off, which is when a learner is reading
  # the card most carefully.
  test "an apostrophe is escaped once, with readings shown" do
    rendered = with_furigana("It's polite")

    assert_equal "It&#39;s polite", rendered
    assert_predicate rendered, :html_safe?
  end

  test "an apostrophe is escaped once, with readings hidden" do
    rendered = with_furigana("It's polite", show: false)

    assert_equal "It&#39;s polite", rendered
    assert_predicate rendered, :html_safe?
  end

end
