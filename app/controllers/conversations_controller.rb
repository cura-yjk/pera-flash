class ConversationsController < ApplicationController
  def new
    @conversation = current_user.conversations.new
    @message = Message.new
  end

  def show
    @conversation = current_user.conversations.find(params[:id])
    @messages = @conversation.messages.order(:created_at)
    @message = Message.new
  end

  def create
    @conversation = current_user.conversations.new(title: "Untitled")

    ActiveRecord::Base.transaction do
      @conversation.save!
      @message = @conversation.messages.new(message_params)
      @message.role = "user"
      @message.save!
    end

    respond_to_new_message
  rescue ActiveRecord::RecordInvalid
    @conversation = current_user.conversations.new
    @message = Message.new(message_params)
    render :new, status: :unprocessable_entity
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

  private

  def message_params
    params.require(:message).permit(:content)
  end

  def respond_to_new_message
    ruby_llm = RubyLLM.chat
    @conversation.messages.each { |m| ruby_llm.add_message(m) }
    response = ruby_llm.with_instructions(Message.system_prompt).ask(@message.content)
    @conversation.messages.create(content: response.content, role: "assistant")
    @conversation.generate_title_from_first_message

    redirect_to conversation_path(@conversation)
  end
end
