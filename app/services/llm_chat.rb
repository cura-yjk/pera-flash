# One place to say who writes Pera's replies, with which model, and on which
# credentials.
#
# The three LLM features -- the chat itself, conversation titling, and flashcard
# generation -- each called RubyLLM.chat directly and inherited whichever
# default the gem happened to ship, so a bundle update could change the model
# with no deploy and no diff.
module LlmChat
  MODEL = "gemini-3.5-flash"
  PROVIDER = :gemini

  # Thinking off. Measured against the chat prompt, with thinking on:
  #
  #   as shipped        first token 16.3s   total 18.2s   (worst seen: 37.9s)
  #   thinkingBudget 0  first token  1.1s   total  3.3s
  #
  # Every token arrived at the very end with thinking on, because the model
  # spends that time reasoning before it emits anything. Correcting a
  # beginner's sentence into a known format is not what a thinking budget is
  # for, and the replies come back just as good.
  #
  # Nested under thinkingConfig deliberately -- generationConfig.thinkingBudget
  # at the top level is rejected as an unknown field.
  THINKING_OFF = { thinkingConfig: { thinkingBudget: 0 } }.freeze

  module_function

  # Every configured key, in the order they should be tried.
  #
  # GEMINI_API_KEYS holds a comma-separated list so keys never reach the repo;
  # GEMINI_API_KEY is still read as a single-key fallback, which is what the
  # test environment and any old config provide.
  def keys
    list = ENV.fetch("GEMINI_API_KEYS", nil).presence || ENV.fetch("GEMINI_API_KEY", "")

    list.split(",").map(&:strip).reject(&:empty?)
  end

  # Yields a chat, and yields a fresh one on the next key if the provider says
  # the current key is out of quota.
  #
  # Quota is per key and these keys are small, so one exhausted key would
  # otherwise take the whole feature down until it reset. Anything other than a
  # quota error is raised immediately: a bad request is not going to succeed on
  # different credentials, and retrying it would spend a second key's budget to
  # produce the same failure.
  #
  # The block must do the whole exchange, not just build the chat, so a retry
  # replays the instructions and history against the new key.
  def with_chat
    exhausted = []

    keys.each do |key|
      return yield chat_on(key)
    rescue RubyLLM::RateLimitError => e
      exhausted << e
      Rails.logger.warn("Gemini key ending #{key.last(6)} is out of quota; trying the next one")
    end

    raise exhausted.last || RubyLLM::Error.new(nil, "No Gemini API key is configured")
  end

  # A chat on one specific key. RubyLLM.context keeps the credential to this
  # chat rather than mutating global config, which two requests being served at
  # once would otherwise race over.
  def chat_on(key)
    RubyLLM.context { |config| config.gemini_api_key = key }
           .chat(model: MODEL, provider: PROVIDER, assume_model_exists: true)
           .with_params(generationConfig: THINKING_OFF)
  end
end
