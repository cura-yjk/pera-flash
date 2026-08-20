# app/models/conversation.rb
class Conversation < ApplicationRecord
  belongs_to :user
  has_many :messages, dependent: :destroy
  has_many :flashcards

  validates :title, presence: true
  before_validation :set_title
  scope :empty, -> { left_joins(:messages).where(messages: { id: nil }) }

  def set_title
    self.title = "Untitled" if title.nil?
  end

  def generate_title_from_first_message
    return unless title == "Untitled"

    first_message = messages.where(role: "user").first
    return unless first_message

    response = RubyLLM.chat.ask(<<~PROMPT)
      Reply with only a short 3-6 word title summarizing the topic of this message.
      No quotes, no trailing punctuation, no explanation — just the title.

      Message: "#{first_message.content}"
    PROMPT

    update(title: response.content.strip)
  end
end
