class Flashcard < ApplicationRecord
  belongs_to :conversation, optional: true
  belongs_to :deck, optional: true
end
