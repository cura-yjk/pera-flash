# One place to say who writes Pera's replies, and with which model.
#
# The three LLM features -- the chat itself, conversation titling, and
# flashcard generation -- each called RubyLLM.chat directly and inherited
# whichever default the gem happened to ship, so a bundle update could change
# the model with no deploy and no diff. Switching provider is now these two
# constants plus a key in config/initializers/ruby_llm.rb.
module LlmChat
  MODEL = "gemini-3.5-flash"
  PROVIDER = :gemini

  module_function

  # Thinking off. Measured against this prompt, with thinking on:
  #
  #   as shipped        first token 16.3s   total 18.2s   (worst seen: 37.9s)
  #   thinkingBudget 0  first token  1.1s   total  3.3s
  #
  # Every token arrived at the very end with thinking on, because the model
  # spends that time reasoning before it emits anything -- no amount of
  # streaming UI can fill a wait that produces no output. The work here is
  # correcting a beginner's sentence into a known format, which is not what a
  # thinking budget is for, and the replies come back just as good: right
  # particle, right format, furigana intact.
  #
  # Nested under thinkingConfig deliberately -- generationConfig.thinkingBudget
  # at the top level is rejected as an unknown field.
  THINKING_OFF = { thinkingConfig: { thinkingBudget: 0 } }.freeze

  # The version is pinned rather than using the floating "-latest" alias: a
  # model that changes under you changes Pera's teaching without a deploy.
  #
  # assume_model_exists skips ruby_llm's bundled registry, which lags behind
  # new releases. The registry only gates the name; the request is unaffected.
  def new_chat
    RubyLLM.chat(model: MODEL, provider: PROVIDER, assume_model_exists: true)
           .with_params(generationConfig: THINKING_OFF)
  end
end
