require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "rejects a user message past the length cap" do
    message = conversations(:lesson).messages.new(role: "user", content: "あ" * (Message::MAX_USER_CONTENT_LENGTH + 1))

    assert_not message.valid?
  end

  # Pera's replies carry grammar tables and run long. Validating them would
  # raise inside MessagesController#answered? and lose the reply entirely.
  test "allows an assistant message past that cap" do
    message = conversations(:lesson).messages.new(role: "assistant",
                                                  content: "a" * (Message::MAX_USER_CONTENT_LENGTH + 1))

    assert message.valid?
  end
end
