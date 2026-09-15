class User < ApplicationRecord
  # :lockable stops an open sign-up page doubling as a password-guessing
  # endpoint. It unlocks on a timer rather than by email -- see
  # config/initializers/devise.rb.
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :lockable
  has_many :conversations, dependent: :destroy
  has_many :decks, dependent: :destroy
end
