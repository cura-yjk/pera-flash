require "test_helper"

class PageTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:starter)
    @deck.flashcards.destroy_all
    30.times { |i| @deck.flashcards.create!(question: "Q#{i}", answer: "A#{i}") }
    @scope = @deck.flashcards.order(:created_at)
  end

  test "hands back one page of records" do
    page = Page.of(@scope, 1, size: 10)

    assert_equal 10, page.records.size
    assert_equal 3, page.pages
    assert_equal 30, page.total
  end

  test "knows where it is in the list" do
    assert_predicate Page.of(@scope, 1, size: 10), :first?
    assert_predicate Page.of(@scope, 3, size: 10), :last?
    assert_not Page.of(@scope, 2, size: 10).first?
    assert_not Page.of(@scope, 2, size: 10).last?
  end

  test "a short list needs no paging" do
    assert_not Page.of(@scope, 1, size: 100).many?
    assert_predicate Page.of(@scope, 1, size: 10), :many?
  end

  # ?page=0 and ?page=99 are both things people type and link to; neither
  # should produce an empty screen.
  test "a page number out of range lands on a real page" do
    assert_equal 1, Page.of(@scope, 0, size: 10).number
    assert_equal 1, Page.of(@scope, -5, size: 10).number
    assert_equal 3, Page.of(@scope, 99, size: 10).number
    assert_equal 1, Page.of(@scope, nil, size: 10).number
    assert_equal 1, Page.of(@scope, "not a number", size: 10).number
  end

  test "an empty list is still one page" do
    @deck.flashcards.destroy_all

    page = Page.of(@deck.flashcards, 1)

    assert_equal 1, page.pages
    assert_empty page.records
    assert_not page.many?
  end

  # count on a grouped relation answers with a hash of counts per group, which
  # would otherwise be compared against page size as if it were a number.
  test "counts rows, not groups, on a grouped scope" do
    grouped = Deck.with_card_counts(users(:learner))

    assert_equal users(:learner).decks.count, Page.of(grouped, 1).total
  end
end
