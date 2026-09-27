# Why a request to Gemini failed, in the terms the learner is told about it.
#
# Every failure used to get the same "couldn't be reached, try again in a
# moment" -- right for a busy model, which most failures are, and wrong for a
# spent quota, where tapping again cannot work for hours. The reason picks the
# explanation (en.yml, failures.*); the log line keeps the exact error.
#
# A 429 can mean the per-minute limit or the day's allowance, and the error
# does not reliably say which, so rate_limited is worded to cover both.
#
# stopped is Gemini ending a reply itself (PeraReply::Blocked). It has done so
# to questions as plain as "What should I learn first?", so the copy does not
# accuse the learner of asking something they shouldn't.
module LlmFailure
  module_function

  def reason(error)
    case error
    when RubyLLM::ServiceUnavailableError, RubyLLM::OverloadedError then :overloaded
    when RubyLLM::RateLimitError then :rate_limited
    when Faraday::TimeoutError then :timeout
    when PeraReply::Blocked then :stopped
    else :other
    end
  end
end
