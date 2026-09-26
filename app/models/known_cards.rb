# The cards a learner already has, looked up by what they say, so a generated
# card that repeats one can be caught before it is saved.
#
# Generation only ever sees the chat it is carding (Conversation#
# messages_for_flashcards), so it cannot repeat itself within a chat -- but
# the same word taught in two chats made two cards. Asking the model not to
# duplicate existing cards was tried before, and it could ignore the request
# (see Conversation#messages_for_flashcards); this is a lookup instead, and
# costs no request.
#
# Not an ActiveRecord model: nothing about it outlives the request.
class KnownCards
  # Whitespace, punctuation and the 〜 that marks where a pattern attaches.
  # NFKC has already folded full-width forms to these.
  NOISE = /[[:space:][:punct:]〜~。、・「」『』]/

  # A card's text reduced to what makes it that card: readings, spacing,
  # punctuation and case removed, so 猫[ねこ]が 好[す]きです。 and 猫が好きです
  # are the same front.
  def self.key(text)
    text.to_s.gsub(FuriganaHelper::ANNOTATION, '\\1').unicode_normalize(:nfkc).gsub(NOISE, "").downcase
  end

  def initialize(user)
    @cards = {}
    Flashcard.for_user(user).select(:id, :question, :answer, :deck_id).find_each { |card| add(card) }
  end

  # The card this front repeats, or nil. Existing cards are indexed by their
  # answer as well as their question: cards made before fronts became Japanese
  # carried the Japanese on the back.
  def match(front)
    key = self.class.key(front)
    key.empty? ? nil : @cards[key]
  end

  # Counts a card as known from here on -- one just built or saved -- so a
  # batch cannot repeat itself either. The first card with a given text wins.
  def add(card)
    [card.question, card.answer].each do |text|
      key = self.class.key(text)
      @cards[key] ||= card unless key.empty?
    end
  end
end
