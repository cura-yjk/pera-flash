require "csv"

class DecksController < ApplicationController
  # Cells a spreadsheet would run as a formula.
  #
  # Excel, Numbers and Sheets all treat a cell starting with one of these as a
  # formula rather than text, so a card reading =HYPERLINK("http://...","Click")
  # becomes a live link in whatever the learner opens their export with -- and
  # card text is partly written by the model, not only by them. Prefixing with
  # an apostrophe is the standard defence: spreadsheets read the rest as text
  # and do not display the apostrophe itself.
  FORMULA_TRIGGERS = ["=", "+", "-", "@", "\t", "\r"].freeze

  # List the current user's decks, annotated with each deck's flashcard
  # count via a LEFT JOIN + COUNT (so decks with zero flashcards still show)
  def index
    @decks = Deck.with_card_counts(current_user)
  end

  # Create a new deck for the current user
  def create
    @deck = current_user.decks.new(deck_params)

    if @deck.save
      redirect_to decks_path, notice: t("decks.created")
    else
      # Re-fetch @decks (same query as #index) since validation failure
      # re-renders the index view, which expects @decks to be present
      @decks = current_user.decks.left_joins(:flashcards)
                           .select("decks.*, COUNT(flashcards.id) AS flashcards_count")
                           .group("decks.id")
                           .order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  # Show a single deck's flashcards, optionally filtered by a search query
  # against question/answer text (case-insensitive)
  def show
    @deck = current_user.decks.find(params[:id])
    @due_count = @deck.flashcards.due.count
    @page = Page.of(@deck.flashcards.matching(params[:query]), params[:page])
    @flashcards = @page.records
  end

  def destroy
    @deck = current_user.decks.find(params[:id])
    @deck.destroy!
    redirect_to decks_path, notice: t("decks.deleted")
  end

  # TODO: not yet implemented
  def export
    @deck = current_user.decks.find(params[:id])

    csv_data = CSV.generate do |csv|
      # Not translated, deliberately. These are column names read by whatever
      # the file is imported into -- Anki maps fields by them -- so they are
      # part of a file format rather than something a person reads. Translating
      # them meant a learner with a Japanese interface exported 問題,答え and a
      # German one Frage,Antwort, quietly producing a different format per
      # language.
      csv << %w[Question Answer]
      @deck.flashcards.each do |flashcard|
        csv << [spreadsheet_safe(flashcard.question), spreadsheet_safe(flashcard.answer)]
      end
    end

    send_data "﻿#{csv_data}",
              filename: "#{@deck.name.parameterize}-flashcards.csv",
              type: "text/csv; charset=utf-8"
  end

  private

  def spreadsheet_safe(text)
    value = text.to_s

    value.start_with?(*FORMULA_TRIGGERS) ? "'#{value}" : value
  end

  # Whitelist deck attributes safe for mass assignment
  def deck_params
    params.require(:deck).permit(:name)
  end
end
