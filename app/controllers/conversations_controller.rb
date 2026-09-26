# Handles the "chat with AI to learn Japanese, then turn it into flashcards" flow
class ConversationsController < ApplicationController
  # Generated cards stream in one at a time; see FlashcardResponses.
  include EventStreaming
  include FlashcardResponses

  # A generation is a second LLM call per press, and the button sits right in
  # the chat -- cheaper to press repeatedly than to type a message.
  # `only:` is not optional here: without it these throttle every action in the
  # controller, so the sixth conversation you merely *open* is refused.
  rate_limit to: 5, within: 1.minute, only: :generate_flashcards,
             by: -> { current_user.id }, with: -> { generation_rate_limited }, name: "generate_burst"
  rate_limit to: 60, within: 1.hour, only: :generate_flashcards,
             by: -> { current_user.id }, with: -> { generation_rate_limited }, name: "generate_hourly"
  # Creating a conversation costs no LLM call, only rows -- limited to keep a
  # script from filling the table.
  rate_limit to: 20, within: 1.minute, by: -> { current_user.id }, only: :create

  # Every chat the user has actually used, newest first. The navbar's "Chat
  # History" link pointed at href="#" until this existed.
  def index
    @page = Page.of(current_user.conversations.started.order(created_at: :desc), params[:page])
    @conversations = @page.records
  end

  # Show a single conversation and its message history, plus a blank
  # Message for the reply form on the page
  def show
    @conversation = current_user.conversations.find(params[:id])
    @messages = @conversation.messages.order(:created_at)
    @message = Message.new
  end

  # Start a new, empty conversation for the current user
  def create
    current_user.conversations.empty.destroy_all
    @conversation = current_user.conversations.empty.first || current_user.conversations.new

    if @conversation.persisted? || @conversation.save
      redirect_to conversation_path(@conversation)
    else
      # No dedicated "new" view/route, so fall back to re-rendering the
      # home page (where conversations presumably get kicked off) on failure
      render "pages/home", status: :unprocessable_entity
    end
  end

  # The rename form, shown in place of the title (see _title.html.erb).
  def edit
    @conversation = current_user.conversations.find(params[:id])
  end

  # Back to the chat either way it is reached: inside the title's turbo frame,
  # Turbo follows the redirect and takes just the frame from the page.
  def update
    @conversation = current_user.conversations.find(params[:id])

    if @conversation.update(params.require(:conversation).permit(:title))
      redirect_to conversation_path(@conversation), status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Turn what has been discussed since the last generation into flashcards.
  #
  # Deliberately not the whole conversation: see
  # Conversation#messages_for_flashcards for why the input is scoped.
  #
  # Streamed when the browser asks for it (flashcard_stream_controller does),
  # and answered whole when it does not. Everything short of a generation --
  # nothing new, rate limited, not found -- is an ordinary turbo_stream either
  # way, which the controller hands to Turbo.
  def generate_flashcards
    @conversation = current_user.conversations.find(params[:id])
    messages = @conversation.messages_for_flashcards

    # Nothing said since the last batch -- answer without paying for a
    # generation that could only return an empty array.
    return render :no_new_material if messages.none?

    generation = FlashcardGeneration.new(@conversation, messages)
    return stream_flashcards(generation) if streaming_requested?

    @flashcards = unless_failed { generation.call }
    return render :generation_failed if @flashcards.nil?

    render_nothing_to_card if @flashcards.empty?
  end

  private

  def generation_rate_limited
    notice = t("conversations.rate_limited")

    respond_to do |format|
      format.turbo_stream { render :generation_rate_limited, locals: { notice: notice }, status: :too_many_requests }
      format.html { redirect_back fallback_location: dashboard_path, alert: notice }
    end
  end
end
