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
end
