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


  # The convention is one reading per kanji, and the prompt says so, but the
  # model writes whole-word annotations often enough that a strict renderer
  # left raw square brackets on screen -- 5 in one real reply, 27 in another.
  # Strengthening the instruction made it worse, so the renderer handles both.
  test "a reading can cover a word with okurigana in it" do
    assert_equal "<ruby>書き出し<rt>かきだし</rt></ruby>",
                 with_furigana("書き出し[かきだし]")
  end

  test "a whole-word reading keeps any kana that follow the word" do
    assert_equal "<ruby>読みがな<rt>よみがな</rt></ruby>について",
                 with_furigana("読みがな[よみがな]について")
  end

  # The hard case: 書き出し[かきだし] and 私は本[ほん] are the same shape --
  # kanji, kana, kanji, bracket. Reading ほん over 私は本 would be worse than
  # the raw brackets, because a learner cannot tell a confident wrong reading
  # from a right one. The kana settle it: き and し appear in かきだし, は does
  # not appear in ほん.
  test "a particle between two words does not get swallowed by the reading" do
    assert_equal "私は<ruby>本<rt>ほん</rt></ruby>", with_furigana("私は本[ほん]")
  end

  test "an unrelated reading falls back to the kanji it follows" do
    assert_equal "食べて<ruby>飲<rt>の</rt></ruby>む", with_furigana("食べて飲[の]む")
  end

  test "hiding readings strips a whole-word annotation too" do
    assert_equal "書き出し", with_furigana("書き出し[かきだし]", show: false)
  end
end
