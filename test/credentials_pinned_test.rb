require "test_helper"

# The suite must never run on a real credential.
#
# test_helper pins the API-key variables before the app boots, but it has to
# name each one -- and dotenv loads .env in the test environment, so any
# variable it misses arrives holding whatever the developer's real key is.
# That already happened once: LlmChat#keys reads GEMINI_API_KEYS first, only
# the singular GEMINI_API_KEY was pinned, and the suite quietly spent live
# quota until a failure printed the key into the output.
#
# This guards the ambient environment rather than any one service, so a new
# variable added to .env without a matching pin fails here instead of on
# someone's bill.
#
# Every assertion below is a bare `assert` with a hand-written message, never
# assert_equal: a failing assert_equal prints the values it compared, which
# for this test is the live key -- into CI logs, on the one run that proves
# the key is exposed.
class CredentialsPinnedTest < ActiveSupport::TestCase
  PINNED = "test-gemini-key-not-a-real-credential".freeze
  VARIABLES = %w[GEMINI_API_KEYS GEMINI_API_KEY].freeze

  test "the keys LlmChat would spend are all pinned test values" do
    keys = LlmChat.keys

    assert keys.any?, "LlmChat has no key configured, so the suite proves nothing about what it would spend"
    assert keys.all?(PINNED), "LlmChat would spend a key that is not the pinned test value"
  end

  test "no Gemini variable carries a real credential" do
    VARIABLES.each do |name|
      keys = ENV.fetch(name, "").split(",").map(&:strip).reject(&:empty?)

      assert keys.all?(PINNED), "#{name} is holding a real credential during the test run"
    end
  end
end
