class FlashcardsSchema < RubyLLM::Schema
  array :flashcards do
    object do
      string :question, description: "The question or prompt side"
      string :answer, description: "The concise answer side"
    end
  end
end
