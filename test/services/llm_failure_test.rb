require "test_helper"

class LlmFailureTest < ActiveSupport::TestCase
  test "a busy model is overloaded" do
    assert_equal :overloaded, LlmFailure.reason(RubyLLM::ServiceUnavailableError.new("high demand"))
    assert_equal :overloaded, LlmFailure.reason(RubyLLM::OverloadedError.new("overloaded"))
  end

  test "a 429 is a rate limit" do
    assert_equal :rate_limited, LlmFailure.reason(RubyLLM::RateLimitError.new("quota"))
  end

  test "no answer in time is a timeout" do
    assert_equal :timeout, LlmFailure.reason(Faraday::TimeoutError.new("timed out"))
  end

  # Never got through at all: "couldn't be reached" is the right thing to say.
  test "a connection that fails is not a timeout" do
    assert_equal :other, LlmFailure.reason(Faraday::ConnectionFailed.new("execution expired"))
  end

  test "anything else is other" do
    assert_equal :other, LlmFailure.reason(RubyLLM::BadRequestError.new("bad"))
    assert_equal :other, LlmFailure.reason(RuntimeError.new("boom"))
  end

  test "every reason has an explanation" do
    %i[overloaded rate_limited timeout other].each do |reason|
      assert I18n.exists?("failures.#{reason}"), "failures.#{reason} is missing from en.yml"
    end
  end
end
