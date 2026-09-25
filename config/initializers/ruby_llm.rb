RubyLLM.configure do |config|
  # Which model and provider are used lives in LlmChat, not here -- these are
  # only credentials. A key for a provider the app is not pointed at is
  # harmless, and means switching back is a one-line change in LlmChat.
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)

  # These calls happen inside a request, with someone watching a spinner.
  # ruby_llm defaults to 120 seconds, which is long enough that a hung
  # provider looks like a hung app.
  config.request_timeout = 30

  # No automatic retries: one tap, one request. ruby_llm's default retried a
  # failed request three more times -- on timeouts, "high demand" 503s, 500s
  # and 429s -- so one tap on a bad Gemini day spent four of the free tier's
  # few daily requests, and a timeout took 4 x 30s = two minutes to report.
  # The learner gets a notice and chooses whether to try again.
  #
  # Moving to the next key when one is out of quota is not a retry and still
  # happens: see LlmChat.with_chat. Google has refused that request, so the
  # next key is the only way it can be answered at all.
  config.max_retries = 0
end
