class Conversation < ApplicationRecord
  belongs_to :user
  has_many :messages, dependent: :destroy

  validates :title, presence: true
  before_validation :set_title

  def set_title
    self.title = "New chat" if title.nil?
  end
end
