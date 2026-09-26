# app/models/conversation.rb
class Conversation < ApplicationRecord
  belongs_to :user
  has_many :messages, dependent: :destroy
  # :nullify, not :destroy -- a card is filed in a deck and reviewed from
  # there, so it outlives the chat it was made in. Without this the database's
  # foreign key refuses the delete, and closing an account raised
  # ActiveRecord::InvalidForeignKey for anyone who had ever saved a card.
  has_many :flashcards, dependent: :nullify

  # What a chat is called before anything has been said in it.
  DEFAULT_TITLE = "Let's chat!"
  # How much of the first message an automatic name takes. Learners can rename
  # a chat to anything up to MAX_TITLE_LENGTH.
  NAME_LENGTH = 40
  MAX_TITLE_LENGTH = 80

  validates :title, presence: true, length: { maximum: MAX_TITLE_LENGTH }
  before_validation :set_title

  # See #messages_for_flashcards.
  FLASHCARD_MESSAGE_LIMIT = 20

  scope :empty, -> { left_joins(:messages).where(messages: { id: nil }) }

  # Message and card counts come back on the conversation rows themselves, so a
  # list of conversations doesn't fire two COUNTs per row. DISTINCT matters:
  # joining messages and flashcards together multiplies the rows for each, and
  # a plain COUNT would report a 3-message chat as having 18 cards.
  scope :with_counts, lambda {
    left_joins(:messages, :flashcards)
      .select("conversations.*",
              "COUNT(DISTINCT messages.id) AS messages_count",
              "COUNT(DISTINCT flashcards.id) AS flashcards_count")
      .group("conversations.id")
  }

  # Conversations someone actually said something in. An abandoned empty chat
  # is noise in a history list -- and #create leaves them behind by design.
  scope :started, -> { with_counts.having("COUNT(messages.id) > 0") }

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
  #
  # At most FLASHCARD_MESSAGE_LIMIT of them, the most recent. The first
  # generation in a chat has no earlier cards to start from, so it used to
  # send the whole conversation: a long chat meant a long prompt, a long list
  # of cards to write, and the slowest generations. Messages older than the
  # limit are not carded -- the next batch starts after this one.
  def messages_for_flashcards
    recent = flashcard_candidates.reorder(created_at: :desc).limit(FLASHCARD_MESSAGE_LIMIT).select(:id)

    messages.order(:created_at).where(id: recent)
  end

  def set_title
    self.title = DEFAULT_TITLE if title.nil?
  end

  # Names the chat after the first thing the learner said, when they say it.
  # Only the default title is replaced, so a later message -- or a chat the
  # learner has already renamed -- keeps its name.
  #
  # This used to ask the model for a 3-6 word summary. That cost a request out
  # of the free tier for every new chat, held up the first reply until it came
  # back, left "Let's chat!" whenever Gemini was busy, and was often worse
  # than the message itself: five chats that began "How does this app work?"
  # came back as "App Functionality Explained".
  def name_after(message)
    return unless title == DEFAULT_TITLE

    update(title: self.class.name_from(message.content))
  end

  # The first line of what was said, without furigana, cut at a word where
  # there is one. Japanese has no spaces to cut at, so it is cut at the length.
  def self.name_from(text)
    line = text.to_s.gsub(FuriganaHelper::ANNOTATION, '\\1').lines.map(&:squish).find(&:present?)
    return DEFAULT_TITLE if line.nil?

    line.truncate(NAME_LENGTH, separator: " ", omission: "…")
  end

  private

  def flashcard_candidates
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
end
