require "application_system_test_case"

# Searching used to mean typing, then finding and pressing a button. This is
# the difference between a search box and a form.
class FlashcardSearchTest < ApplicationSystemTestCase
  setup do
    @user = users(:learner)
    deck = decks(:starter)
    @cat = deck.flashcards.create!(question: "How do you say cat?", answer: "猫[ねこ]")
    @book = deck.flashcards.create!(question: "How do you say book?", answer: "本[ほん]")
    sign_in_as(@user)
  end

  test "typing narrows the list without pressing anything" do
    visit flashcards_path
    assert_text @cat.question
    assert_text @book.question

    type_search("cat")

    assert_text @cat.question
    assert_no_text @book.question
  end

  test "clearing the box brings everything back" do
    visit flashcards_path
    type_search("cat")
    assert_no_text @book.question

    type_search("")

    assert_text @book.question
  end

  test "says so when nothing matches" do
    visit flashcards_path

    type_search("qwertyuiop")

    assert_text(/no flashcards match/i)
  end

  # The field lives outside the frame that is replaced, so what has been typed
  # survives each round trip -- otherwise the box would empty itself under the
  # reader's hands on every keystroke.
  test "the box keeps what was typed" do
    visit flashcards_path

    type_search("cat")

    assert_equal "cat", find("form[data-controller='live-search'] input[name='query']").value
  end

  # A search should be shareable, and the back button should undo it.
  test "the address bar follows the search" do
    visit flashcards_path

    type_search("cat")
    assert_no_text @book.question

    assert_match(/query=cat/, page.current_url)
  end

  # A learner accumulating cards is the whole point of the app, and the index
  # used to render every one of them on every visit.
  test "long lists are paged" do
    25.times { |i| decks(:starter).flashcards.create!(question: "Filler #{i}", answer: "-") }

    visit flashcards_path

    assert_text(/Page 1 of/i)
    assert_operator page.all(".flashcard-preview-card").size, :<=, Page::DEFAULT_SIZE

    click_on "Next"

    assert_text(/Page 2 of/i)
  end

  private

  # Fires the input event the controller listens for, and waits out its pause.
  #
  # Scoped to this page's form: the navbar carries a search box with the same
  # field name, and an unscoped selector types into that one instead.
  def type_search(text)
    page.execute_script(<<~JS, text)
      const field = document.querySelector("form[data-controller='live-search'] input[name='query']");
      field.value = arguments[0];
      field.dispatchEvent(new Event("input", { bubbles: true }));
    JS
  end
end
