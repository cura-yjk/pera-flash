require "application_system_test_case"

# Editing a card by hand is only reachable by clicking it, and that click goes
# through a turbo frame: the link names one, the layout provides one, and the
# edit template answers with one. All three have to agree, and nothing but a
# browser notices when they stop -- the controller test passes either way,
# because the response is correct in isolation.
#
# They did stop agreeing. The link asked for "modal-<id>", which existed
# nowhere, so Turbo fell back to the frame around the grid, failed to find that
# in the response, and wrote "Content missing" over the card list.
class EditingACardTest < ApplicationSystemTestCase
  setup do
    @user = users(:learner)
    @deck = decks(:starter)
    sign_in_as(@user)
  end

  test "clicking a card opens its edit form" do
    @deck.flashcards.create!(question: "What does 猫 mean?", answer: "Cat")

    visit flashcards_path
    open_card("What does 猫 mean?")

    assert_text "Edit Flashcard"
    assert_field "flashcard[question]", with: "What does 猫 mean?"
    assert_field "flashcard[answer]", with: "Cat"
  end

  test "the card list is still there behind it" do
    @deck.flashcards.create!(question: "What does 犬 mean?", answer: "Dog")

    visit flashcards_path
    open_card("What does 犬 mean?")

    assert_no_text "Content missing"
    assert_text "What does 犬 mean?"
  end

  test "an edit made in it sticks" do
    card = @deck.flashcards.create!(question: "Typo here", answer: "Cat")

    visit flashcards_path
    open_card("Typo here")
    fill_in "flashcard[question]", with: "What does 猫 mean?"
    click_and_confirm("Save", expect: "What does 猫 mean?")

    assert_equal "What does 猫 mean?", card.reload.question
  end

  private

  # The whole card is the link. Clicking its text is what a learner does, but
  # a driver click there is the flakiest kind, so this goes to the anchor.
  def open_card(question)
    card = find("p", text: question, match: :first).ancestor("a")
    card.click
    return if page.has_text?("Edit Flashcard", wait: 3)

    card.evaluate_script("this.click()")
    assert_text "Edit Flashcard", wait: 10
  end
end
