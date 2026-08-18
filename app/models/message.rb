class Message < ApplicationRecord
  belongs_to :conversation

  # Enforces valid roles: "system", "user", or "assistant"
  enum :role, { system: "system", user: "user", assistant: "assistant" }, validates: true
  validates :content, presence: true
end
