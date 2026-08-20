class ConversationsController < ApplicationController
  def show
    @conversation = current_user.conversations.find(params[:id])
    @messages = @conversation.messages.order(:created_at)
    @message = Message.new
  end

  def create
    @conversation = Conversation.new
    @conversation.user = current_user
    if @conversation.save
      redirect_to conversation_path(@conversation)
    else
      render "pages/home", status: :unprocessable_entity
    end
  end

  def generate_flashcards # rubocop:disable Metrics/MethodLength
    @conversation = current_user.conversations.find(params[:id])
    transcript = @conversation.messages.order(:created_at)
                              .map { |m| "#{m.role}: #{m.content}" }.join("\n\n")

    response = RubyLLM.chat.with_schema(FlashcardsSchema).ask(<<~PROMPT)
      Based on this conversation, generate 3-5 flashcards covering the key
      concepts discussed. Question = prompt, answer = concise answer.

      Conversation:
      #{transcript}
      These should be new unique flashcards. Previous flashcards made:
      #{@conversation.flashcards.pluck(:question).join(', ')}
    PROMPT

    @flashcards = response.content["flashcards"].map do |card|
      @conversation.flashcards.build(question: card["question"], answer: card["answer"])
    end
  end
end
