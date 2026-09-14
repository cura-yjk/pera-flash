RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]

  # These calls happen inside a request, with someone watching a spinner.
  # ruby_llm defaults to 120 seconds, which is long enough that a hung
  # provider looks like a hung app.
  config.request_timeout = 30
end
