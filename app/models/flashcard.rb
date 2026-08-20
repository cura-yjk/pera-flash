class Flashcard < ApplicationRecord
  belongs_to :conversation, optional: true
  belongs_to :deck, optional: true

  validates :question, presence: true
  validates :answer, presence: true
end
