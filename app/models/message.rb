class Message < ApplicationRecord
  belongs_to :conversation

  # Enforces valid roles: "system", "user", or "assistant"
  enum :role, { system: "system", user: "user", assistant: "assistant" }, validates: true
  # Long enough for any practice sentence or question, short enough that one
  # paste cannot turn every later reply into an expensive request: the whole
  # conversation is replayed to the model on each turn, so an oversized message
  # is paid for again and again rather than once.
  #
  # Applied to user messages only. Pera's own replies carry grammar tables and
  # routinely run longer, and a validation failure there would raise inside
  # MessagesController#answered? and cost the user the reply they waited for.
  MAX_USER_CONTENT_LENGTH = 2_000

  validates :content, presence: true
  validates :content, length: { maximum: MAX_USER_CONTENT_LENGTH }, if: :user?
end
