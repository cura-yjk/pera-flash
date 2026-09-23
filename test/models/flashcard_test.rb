require "test_helper"

class FlashcardTest < ActiveSupport::TestCase
  setup { @card = flashcards(:neko_card) }

  # --- ownership ------------------------------------------------------------

  # A card reaches its owner through either association. This used to differ
  # between screens: cards with no conversation were invisible in the index
  # while still showing in their deck.
  test "for_user finds cards owned through a deck alone" do
    card = Deck.create!(user: users(:learner), name: "Deck only")
               .flashcards.create!(question: "Q", answer: "A")

    assert_includes Flashcard.for_user(users(:learner)), card
  end

  test "for_user finds cards owned through a conversation alone" do
    card = conversations(:lesson).flashcards.create!(question: "Q", answer: "A")

    assert_includes Flashcard.for_user(users(:learner)), card
  end

  test "for_user excludes another user's cards" do
    theirs = conversations(:other_users_lesson).flashcards.create!(question: "Q", answer: "A")

    assert_not_includes Flashcard.for_user(users(:learner)), theirs
  end

  # --- scheduling -----------------------------------------------------------

  test "a new card answered good comes back tomorrow" do
    @card.review!("good")

    assert_in_delta Flashcard::FIRST_GOOD_INTERVAL, @card.interval_days, 0.001
    assert_in_delta 1.day.from_now, @card.due_at, 5
    assert_equal 1, @card.review_count
  end

  test "a new card answered easy skips further ahead" do
    @card.review!("easy")

    assert_in_delta Flashcard::FIRST_EASY_INTERVAL, @card.interval_days, 0.001
  end

  test "intervals grow by the card's ease on repeated success" do
    @card.review!("good")                        # 1 day
    first = @card.interval_days
    @card.review!("good")                        # 1 * 2.5

    assert_in_delta first * Flashcard::STARTING_EASE, @card.interval_days, 0.001
  end

  test "easy grows faster than good, and raises ease" do
    @card.review!("good")
    @card.review!("easy")

    assert_in_delta Flashcard::STARTING_EASE + 0.15, @card.ease, 0.001
    assert_operator @card.interval_days, :>, Flashcard::STARTING_EASE
  end

  test "forgetting sends the card back to today and lowers ease" do
    @card.review!("easy")
    @card.review!("again")

    assert_in_delta 0.0, @card.interval_days, 0.001
    assert_operator @card.due_at, :<=, Time.current + 1
    assert_equal 1, @card.lapse_count
    assert_operator @card.ease, :<, Flashcard::STARTING_EASE + 0.15
  end

  # The path that was broken: forget a card, then get it right again.
  #
  # `forgot` sets the interval to 0, and the grade used to ask "has this been
  # studied before?" before multiplying. A lapsed card answered that yes, so it
  # multiplied 0 by its ease and stayed at 0 -- due immediately, for ever. The
  # cards in a real deck that had been answered a dozen times were sitting at
  # interval 0 because of it, and the review queue never emptied.
  test "a forgotten card starts growing again when it is answered" do
    @card.review!("easy")
    @card.review!("again")
    assert_in_delta 0.0, @card.interval_days, 0.001, "a lapse should reset the interval"

    @card.review!("good")

    assert_in_delta Flashcard::FIRST_GOOD_INTERVAL, @card.interval_days, 0.001
    assert_operator @card.due_at, :>, Time.current, "it should be scheduled forward, not left due"
  end

  test "a forgotten card answered easy restarts at the easy interval" do
    @card.review!("good")
    @card.review!("again")

    @card.review!("easy")

    assert_in_delta Flashcard::FIRST_EASY_INTERVAL, @card.interval_days, 0.001
  end

  # The symptom as a learner meets it: the card stays in front of them.
  test "a forgotten card leaves the due queue once it is answered" do
    @card.review!("again")
    assert_includes Flashcard.due, @card

    @card.review!("good")

    assert_not_includes Flashcard.due, @card
  end

  # Answering correctly repeatedly after a lapse has to compound, not sit at
  # the restart value.
  test "intervals compound again after a lapse" do
    @card.review!("again")
    @card.review!("good")
    first = @card.interval_days

    @card.review!("good")

    assert_operator @card.interval_days, :>, first
  end

  # Without a floor, a card missed repeatedly would come back so often it
  # stops being a review and becomes a wall.
  test "ease never falls below the minimum" do
    20.times { @card.review!("again") }

    assert_in_delta Flashcard::MINIMUM_EASE, @card.ease, 0.001
  end

  test "an unknown grade is refused" do
    assert_raises(ArgumentError) { @card.review!("brilliant") }
  end

  # --- struggling -----------------------------------------------------------

  test "struggling finds cards forgotten more than once" do
    @card.review!("easy")
    Flashcard::STRUGGLING_LAPSES.times { @card.review!("again") }

    assert_includes Flashcard.for_user(users(:learner)).struggling, @card
  end

  # One lapse is a bad day, not a gap.
  test "a single lapse is not yet struggling" do
    @card.review!("again")

    assert_not_includes Flashcard.for_user(users(:learner)).struggling, @card
  end

  test "struggling puts the most-forgotten card first" do
    worst = conversations(:lesson).flashcards.create!(question: "worst", answer: "A", lapse_count: 9)
    mild = conversations(:lesson).flashcards.create!(question: "mild", answer: "A", lapse_count: 2)

    order = Flashcard.where(id: [mild.id, worst.id]).struggling.map(&:question)

    assert_equal %w[worst mild], order
  end

  # --- queues ---------------------------------------------------------------

  test "due includes never-studied cards and excludes ones scheduled ahead" do
    never = conversations(:lesson).flashcards.create!(question: "Q", answer: "A")
    @card.review!("easy")   # pushed days out

    due = Flashcard.for_user(users(:learner)).due

    assert_includes due, never
    assert_not_includes due, @card
  end

  test "review order puts never-studied cards first, then most overdue" do
    never = conversations(:lesson).flashcards.create!(question: "new", answer: "A")
    overdue = conversations(:lesson).flashcards.create!(question: "overdue", answer: "A",
                                                       due_at: 3.days.ago, review_count: 1)
    slightly = conversations(:lesson).flashcards.create!(question: "slightly", answer: "A",
                                                        due_at: 1.hour.ago, review_count: 1)

    order = Flashcard.where(id: [never.id, overdue.id, slightly.id]).in_review_order.map(&:question)

    assert_equal %w[new overdue slightly], order
  end

  # Readings come off once the schedule trusts the card: past that point they
  # are the answer rather than a hint.
  test "a card scheduled well out counts as mastered" do
    card = Flashcard.new(interval_days: Flashcard::MASTERED_INTERVAL_DAYS, lapse_count: 0)

    assert card.mastered?
  end

  test "a card still being learned is not mastered" do
    card = Flashcard.new(interval_days: 3.0, lapse_count: 0)

    assert_not card.mastered?
  end

  test "a card with a long interval but repeated lapses is not mastered" do
    card = Flashcard.new(interval_days: 30.0, lapse_count: Flashcard::STRUGGLING_LAPSES)

    assert_not card.mastered?
  end

end
