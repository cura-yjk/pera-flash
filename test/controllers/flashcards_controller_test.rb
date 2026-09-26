require "test_helper"

# This file was the generated stub, so every way a learner edits their own
# cards by hand went unexercised: the index they search, the form they fix a
# typo in, the delete button, and the save that files a generation into a deck.
class FlashcardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:learner)
    @deck = decks(:starter)
    @conversation = conversations(:lesson)
    sign_in @user
  end

  test "requires authentication" do
    sign_out @user

    get flashcards_path

    assert_redirected_to new_user_session_path
  end

  # --- index ----------------------------------------------------------------

  test "lists the learner's own cards" do
    card = own_card(question: "What does 猫 mean?")

    get flashcards_path

    assert_response :success
    assert_match card.question, response.body
  end

  # for_user reaches cards through their deck or their conversation, so a card
  # belonging to neither of this learner's must not appear.
  test "leaves another learner's cards out" do
    stranger_card = stranger_deck.flashcards.create!(question: "What does 魚 mean?", answer: "Fish")

    get flashcards_path

    assert_response :success
    assert_no_match stranger_card.question, response.body
  end

  test "filters by the query, matching answers as well as questions" do
    kanji = own_card(question: "What does 鳥 mean?", answer: "Bird")
    other = own_card(question: "What does 山 mean?", answer: "Mountain")

    get flashcards_path(query: "Bird")

    assert_match kanji.question, response.body
    assert_no_match other.question, response.body
  end

  test "shows the newest card first" do
    own_card(question: "Older card", created_at: 2.days.ago)
    own_card(question: "Newer card", created_at: 1.minute.ago)

    get flashcards_path

    assert_operator response.body.index("Newer card"), :<, response.body.index("Older card")
  end

  test "pages the list" do
    (Page::DEFAULT_SIZE + 1).times { |i| own_card(question: "Card #{i}", created_at: i.minutes.ago) }

    get flashcards_path

    # The oldest of the batch is the one pushed onto page two.
    assert_no_match "Card #{Page::DEFAULT_SIZE}", response.body
  end

  # --- edit and update ------------------------------------------------------

  test "renders the edit form for a card the learner owns" do
    card = own_card(question: "What does 犬 mean?")

    get edit_flashcard_path(card)

    assert_response :success
    assert_match card.question, response.body
  end

  test "does not find another learner's card to edit" do
    stranger_card = stranger_deck.flashcards.create!(question: "Not yours", answer: "No")

    get edit_flashcard_path(stranger_card)

    assert_response :not_found
  end

  test "saves an edit and returns to the index" do
    card = own_card(question: "Typo here", answer: "Cat")

    patch flashcard_path(card), params: { flashcard: { question: "Fixed", answer: "Cat" } }

    assert_redirected_to flashcards_path
    assert_equal "Fixed", card.reload.question
  end

  test "moves a card to another deck" do
    card = own_card
    destination = @user.decks.create!(name: "Kanji")

    patch flashcard_path(card), params: { flashcard: { deck_id: destination.id } }

    assert_equal destination, card.reload.deck
  end

  test "refuses to blank out a question, and says so on the form" do
    card = own_card(question: "Keep me")

    patch flashcard_path(card), params: { flashcard: { question: "" } }

    assert_response :unprocessable_entity
    assert_equal "Keep me", card.reload.question
  end

  test "does not find another learner's card to update" do
    stranger_card = stranger_deck.flashcards.create!(question: "Not yours", answer: "No")

    patch flashcard_path(stranger_card), params: { flashcard: { question: "Mine now" } }

    assert_response :not_found
    assert_equal "Not yours", stranger_card.reload.question
  end

  # --- destroy --------------------------------------------------------------

  test "deletes a card" do
    card = own_card

    assert_difference -> { Flashcard.count }, -1 do
      delete flashcard_path(card)
    end

    assert_redirected_to flashcards_path
  end

  # The delete button sits on a card partial shared by the dashboard, the index
  # and a deck page, so it has to return to whichever one it was pressed on.
  test "returns to the page the delete was pressed on" do
    card = own_card

    delete flashcard_path(card), headers: { "HTTP_REFERER" => deck_path(@deck) }

    assert_redirected_to deck_path(@deck)
  end

  test "does not find another learner's card to delete" do
    stranger_card = stranger_deck.flashcards.create!(question: "Not yours", answer: "No")

    assert_no_difference -> { Flashcard.count } do
      delete flashcard_path(stranger_card)
    end

    assert_response :not_found
  end

  # --- create ---------------------------------------------------------------

  test "files saved cards in a deck named after the conversation" do
    post conversation_flashcards_path(@conversation), params: saving("猫", "Cat"), as: :turbo_stream

    deck = @user.decks.find_by(name: @conversation.title)

    assert_not_nil deck, "a deck named after the conversation should be created on first save"
    assert_equal ["猫"], deck.flashcards.pluck(:question)
  end

  test "reuses that deck on a second save rather than making another" do
    post conversation_flashcards_path(@conversation), params: saving("猫", "Cat"), as: :turbo_stream

    assert_no_difference -> { @user.decks.count } do
      post conversation_flashcards_path(@conversation), params: saving("犬", "Dog"), as: :turbo_stream
    end
  end

  test "leaves a confirmation in the chat" do
    assert_difference -> { @conversation.messages.count }, 1 do
      post conversation_flashcards_path(@conversation), params: saving("猫", "Cat"), as: :turbo_stream
    end

    assert_equal "assistant", @conversation.messages.order(:created_at).last.role
  end

  # --- duplicates -------------------------------------------------------------

  test "skips a card the learner already has, whichever deck it is in" do
    own_card(question: "猫[ねこ]", answer: "cat")

    assert_no_difference -> { Flashcard.count } do
      post conversation_flashcards_path(@conversation), params: saving("猫", "Cat"), as: :turbo_stream
    end
  end

  test "saves the new cards in a batch and skips only the known one" do
    own_card(question: "猫[ねこ]", answer: "cat")
    cards = { "0" => { question: "猫", answer: "Cat" }, "1" => { question: "犬[いぬ]", answer: "dog" } }

    post conversation_flashcards_path(@conversation), params: { conversation: { flashcards: cards } },
                                                     as: :turbo_stream

    assert_equal ["犬[いぬ]"], @conversation.flashcards.where.not(id: flashcards(:neko_card)).pluck(:question)
  end

  test "a batch cannot save the same card twice" do
    cards = { "0" => { question: "犬[いぬ]", answer: "dog" }, "1" => { question: "犬", answer: "Dog" } }

    assert_difference -> { Flashcard.count }, 1 do
      post conversation_flashcards_path(@conversation), params: { conversation: { flashcards: cards } },
                                                       as: :turbo_stream
    end
  end

  test "the confirmation says what was left out" do
    own_card(question: "猫[ねこ]", answer: "cat")
    cards = { "0" => { question: "猫", answer: "Cat" }, "1" => { question: "犬", answer: "dog" } }

    post conversation_flashcards_path(@conversation), params: { conversation: { flashcards: cards } },
                                                     as: :turbo_stream

    confirmation = @conversation.messages.order(:created_at).last.content
    assert_match(/1 card added/, confirmation)
    assert_match(/1 was already in your flashcards/, confirmation)
  end

  test "a save of nothing but known cards says so, and still ends the batch" do
    own_card(question: "猫[ねこ]", answer: "cat")

    post conversation_flashcards_path(@conversation), params: saving("猫", "Cat"), as: :turbo_stream

    assert_match(/already in your flashcards/, @conversation.messages.order(:created_at).last.content)
    assert_empty @conversation.reload.messages_for_flashcards
  end

  # The confirmation is written after the cards, and was counted as something
  # new to card: generating again straight after a save spent a request on it.
  test "straight after a save the chat has nothing new to card" do
    post conversation_flashcards_path(@conversation), params: saving("犬", "dog"), as: :turbo_stream

    assert_empty @conversation.reload.messages_for_flashcards
  end

  test "redirects back to the conversation when asked for HTML" do
    post conversation_flashcards_path(@conversation), params: saving("猫", "Cat")

    assert_redirected_to conversation_path(@conversation)
  end

  # The list comes from the client, not from the generation that produced it.
  test "refuses to write more than MAX_CARDS_PER_SAVE in one request" do
    cards = (FlashcardsController::MAX_CARDS_PER_SAVE + 1).times.to_h do |i|
      [i.to_s, { question: "Q#{i}", answer: "A#{i}" }]
    end

    assert_no_difference -> { Flashcard.count } do
      post conversation_flashcards_path(@conversation),
           params: { conversation: { flashcards: cards } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
  end

  test "does not save into another learner's conversation" do
    assert_no_difference -> { Flashcard.count } do
      post conversation_flashcards_path(conversations(:other_users_lesson)),
           params: saving("猫", "Cat"), as: :turbo_stream
    end

    assert_response :not_found
  end

  # --- show -----------------------------------------------------------------

  # `resources :flashcards` routes GET /flashcards/:id, but there is no show
  # action and no template; the path is only ever used with method: :delete.
  # Recorded so that a template appearing later is a deliberate choice.
  test "a card has no page of its own" do
    get flashcard_path(own_card)

    assert_response :not_found
  end

  private

  def own_card(question: "What does 猫 mean?", answer: "Cat", created_at: Time.current)
    @deck.flashcards.create!(question: question, answer: answer, created_at: created_at)
  end

  def stranger_deck
    @stranger_deck ||= users(:other).decks.create!(name: "Somebody else's deck")
  end

  def saving(question, answer)
    { conversation: { flashcards: { "0" => { question: question, answer: answer } } } }
  end
end
