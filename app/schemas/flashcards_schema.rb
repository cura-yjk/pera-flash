class FlashcardsSchema < RubyLLM::Schema
  # The most cards one generation returns. Generation is a single request that
  # shows nothing until the whole JSON list is written, so its time grows with
  # every card -- and Heroku ends any request at 30 seconds. Ten covers what a
  # stretch of chat actually teaches; the prompt asks for the most useful ten
  # when there is more, and the controller trims in case the model does not.
  MAX_CARDS = 10

  array :flashcards, max_items: MAX_CARDS do
    object do
      string :question, description: "The question or prompt side"
      string :answer, description: "The concise answer side"
    end
  end
end
