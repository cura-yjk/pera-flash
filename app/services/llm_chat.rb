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

  # The version is pinned rather than using the floating "-latest" alias: a
  # model that changes under you changes Pera's teaching without a deploy.
  #
  # assume_model_exists skips ruby_llm's bundled registry, which lags behind
  # new releases. The registry only gates the name; the request is unaffected.
  def new_chat
    RubyLLM.chat(model: MODEL, provider: PROVIDER, assume_model_exists: true)
  end
end
