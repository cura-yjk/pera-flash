# app/models/conversation.rb
class Conversation < ApplicationRecord
  belongs_to :user
  has_many :messages, dependent: :destroy
  has_many :flashcards

  validates :title, presence: true
  before_validation :set_title
  scope :empty, -> { left_joins(:messages).where(messages: { id: nil }) }

  # Messages worth generating flashcards from: everything said since the last
  # time cards were made, rather than the whole conversation every time.
  #
  # The old behaviour sent the full transcript on every generation and asked
  # the model to "focus on the MOST RECENT topics" while also not duplicating
  # the existing cards -- two instructions in tension, both of which it could
  # ignore. Scoping the input makes duplication structurally impossible instead
  # of a request, and keeps the cost of a generation flat as a conversation
  # grows rather than climbing with it.
  #
  # One message before the cutoff comes along as lead-in, so a topic already
  # under way when the last cards were made still has its opening line.
  def messages_for_flashcards
    ordered = messages.order(:created_at)
    since = flashcards.maximum(:created_at)
    return ordered if since.nil?

    fresh = ordered.where("messages.created_at > ?", since)
    # Lead-in only accompanies new material; on its own it is old news, and
    # returning it would trigger a generation with nothing new to card.
    return fresh if fresh.empty?

    lead_in = ordered.where(created_at: ..since).last
    return fresh if lead_in.nil?

    ordered.where(id: [lead_in.id] + fresh.ids)
  end

  def set_title
    self.title = "Let's chat!" if title.nil?
  end

  def generate_title_from_first_message
    return unless title == "Let's chat!"

    first_message = messages.where(role: "user").first
    return unless first_message

    update(title: titled_from(first_message))
  rescue StandardError => e
    # Cosmetic. The conversation keeps its default title, which is a far better
    # outcome than failing the message that triggered this.
    Rails.logger.warn("Could not title conversation #{id}: #{e.class}: #{e.message}")
  end

  def titled_from(message)
    LlmChat.new_chat.ask(<<~PROMPT).content.strip
      Reply with only a short 3-6 word title summarizing the topic of this message.
      No quotes, no trailing punctuation, no explanation — just the title.

      Message: "#{message.content}"
    PROMPT
  end
end
