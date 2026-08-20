class Deck < ApplicationRecord
  belongs_to :user
  has_many :flashcards, dependent: :nullify

  validates :name, presence: true
end
