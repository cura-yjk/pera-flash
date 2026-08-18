class DecksController < ApplicationController
  def index
    @decks = Deck.all
  end

  def create
    @deck = Deck.new
    raise
  end
end
