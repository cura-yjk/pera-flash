class FlashcardsController < ApplicationController
  # A generation returns a handful of cards; this is the ceiling on what one
  # request may write, since the list comes from the client rather than from
  # the generation that produced it.
  MAX_CARDS_PER_SAVE = 50

  rate_limit to: 30, within: 1.minute, by: -> { current_user.id }, only: :create

  def create
    conversation = current_user.conversations.find(params[:conversation_id])
    cards = params.require(:conversation).permit(flashcards: %i[question answer])

    return head :unprocessable_entity if cards[:flashcards].to_h.size > MAX_CARDS_PER_SAVE

    created, skipped = save_cards(conversation, cards[:flashcards])
    @message = finish_batch(conversation, created.size, skipped)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to conversation_path(conversation), notice: t("flashcards.saved") }
    end
  end

  def index
    @page = Page.of(Flashcard.for_user(current_user).matching(params[:query]).order(created_at: :desc),
                    params[:page])
    @flashcards = @page.records
  end

  def edit
    @flashcard = current_user_flashcard(params[:id])
    @decks = current_user.decks
  end

  def update
    @flashcard = current_user_flashcard(params[:id])
    if @flashcard.update(flashcard_params)
      redirect_to flashcards_path, notice: t("flashcards.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @flashcard = current_user_flashcard(params[:id])
    @flashcard.destroy!
    redirect_to request.referer || flashcards_path, notice: t("flashcards.deleted")
  end

  private

  # A conversation's cards land in a deck named after it, created on first save.
  # A card the learner already has -- in any deck, or earlier in this batch --
  # is skipped rather than saved twice; see KnownCards. Checked here and not
  # trusted from the preview, since the learner may have edited the front.
  # Returns the cards saved and how many were skipped.
  def save_cards(conversation, cards)
    known = KnownCards.new(current_user)
    deck = nil

    created = cards.each_value.filter_map do |card|
      next if known.match(card[:question])

      deck ||= current_user.decks.find_or_create_by!(name: conversation.title.presence || "Untitled Deck")
      conversation.flashcards.create!(card.merge(deck: deck)).tap { |saved| known.add(saved) }
    end
    [created, cards.to_h.size - created.size]
  end

  # The confirmation in the chat, then the end of the batch. In that order:
  # the confirmation is a message, and marking the conversation carded after
  # it keeps it from counting as something new to card.
  def finish_batch(conversation, added, skipped)
    message = conversation.messages.create!(role: "assistant", content: "✅ #{confirmation(added, skipped)}")
    conversation.mark_carded!
    message
  end

  # Shown in the chat as a system notification -- see messages/_message.
  def confirmation(added, skipped)
    return t("flashcards.none_added", count: skipped) if added.zero? && skipped.positive?

    [t("flashcards.added", count: added, path: flashcards_path),
     (t("flashcards.skipped", count: skipped) if skipped.positive?)].compact.join(" ")
  end

  def flashcard_params
    params.require(:flashcard).permit(:question, :answer, :deck_id)
  end

  def current_user_flashcard(id)
    Flashcard.for_user(current_user).find(id)
  end
end
