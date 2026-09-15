# One page of a list, and what a view needs to offer the next and previous.
#
# Nothing here was paginated: the flashcard index rendered every card the
# learner owned, every time, and the whole point of the app is accumulating
# cards. A gem would do this too, but the whole of it is a limit, an offset and
# two booleans, and this way the markup and its translations stay ours.
class Page
  DEFAULT_SIZE = 24

  attr_reader :number, :size, :total, :records

  def self.of(scope, number, size: DEFAULT_SIZE)
    new(scope, number, size: size)
  end

  def initialize(scope, number, size: DEFAULT_SIZE)
    @size = size
    @total = count_of(scope)
    @number = clamp(number)
    @records = scope.limit(size).offset((@number - 1) * size)
  end

  def pages = [(total / size.to_f).ceil, 1].max

  def first? = number <= 1

  def last? = number >= pages

  def many? = pages > 1

  private

  # The GROUP BY has to stay. Stripping it to count rows counts join rows
  # instead -- one deck with thirty cards came back as thirty decks. Left in
  # place, count answers with a hash of counts per group, whose size is the
  # number of rows the page will show.
  def count_of(scope)
    counted = scope.except(:select, :order).count

    counted.is_a?(Hash) ? counted.size : counted
  end

  # Out of range in either direction lands on a real page rather than an empty
  # one: ?page=0 and ?page=99 are both things people type and link to.
  def clamp(requested)
    requested.to_i.clamp(1, pages)
  end
end
