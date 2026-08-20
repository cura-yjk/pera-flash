class UsersController < ApplicationController
  def dashboard
    @conversations = current_user.conversations.order(created_at: :asc)
    # @deck = current_user.decks
    @deck_count = 0
    @flashcard_count = 0
    @random_flashcard = nil
    @decks = []
  end
end
