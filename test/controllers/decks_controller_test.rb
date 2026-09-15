require "test_helper"

# This file was the generated stub. Nothing rendered the deck page, which is
# how it shipped with broken markup that only Brakeman's parser noticed.
class DecksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:learner)
    @deck = decks(:starter)
  end

  test "requires authentication" do
    sign_out users(:learner)
    get deck_path(@deck)

    assert_redirected_to new_user_session_path
  end

  test "lists the decks with their card counts" do
    @deck.flashcards.create!(question: "Q", answer: "A")

    get decks_path

    assert_response :success
    assert_match @deck.name, response.body
  end

  test "shows a deck and its cards" do
    card = @deck.flashcards.create!(question: "猫[ねこ]とは?", answer: "cat")

    get deck_path(@deck)

    assert_response :success
    assert_match "cat", response.body
    assert_match(/<ruby>猫<rt>ねこ<\/rt><\/ruby>/, response.body)
    assert_select "form[action=?]", deck_path(@deck)
  end

  test "searches within the deck" do
    @deck.flashcards.create!(question: "About cats", answer: "猫")
    @deck.flashcards.create!(question: "About books", answer: "本")

    get deck_path(@deck, query: "cats")

    assert_match "About cats", response.body
    assert_no_match(/About books/, response.body)
  end

  test "refuses another user's deck" do
    theirs = Deck.create!(user: users(:other), name: "Theirs")

    get deck_path(theirs)

    assert_response :not_found
  end

  test "creates a deck" do
    assert_difference -> { users(:learner).decks.count }, 1 do
      post decks_path, params: { deck: { name: "New deck" } }
    end
  end

  test "deletes a deck" do
    assert_difference -> { users(:learner).decks.count }, -1 do
      delete deck_path(@deck)
    end
  end
end
