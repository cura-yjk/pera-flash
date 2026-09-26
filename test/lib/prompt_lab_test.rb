require "test_helper"

# Running the lab is a real request per case, so here Gemini is stubbed at
# the HTTP boundary: what is tested is how a run reacts to each kind of answer.
class PromptLabTest < ActiveSupport::TestCase
  test "seeds every case as a chat of its own" do
    learner = PromptLab.seed!

    assert_equal PromptLab::CASES.map { |c| c[:title] }.sort, learner.conversations.pluck(:title).sort
    PromptLab::CASES.each do |kase|
      conversation = learner.conversations.find_by!(title: kase[:title])
      assert_equal kase[:messages].map(&:last), conversation.messages.order(:created_at).pluck(:content),
                   "#{kase[:title]}: messages out of order"
    end
  end

  test "the long chat is longer than generation will read" do
    long = PromptLab::CASES.find { |c| c[:title].start_with?("Long chat") }

    assert_operator long[:messages].size, :>, Conversation::FLASHCARD_MESSAGE_LIMIT
  end

  test "seeding again replaces the lab learner's data instead of adding to it" do
    PromptLab.seed!
    learner = PromptLab.seed!

    assert_equal PromptLab::CASES.size, learner.conversations.count
    assert_equal PromptLab::DECK[:cards].size, Flashcard.for_user(learner).count
  end

  # db/seeds.rb deletes everyone; this must not.
  test "leaves every other learner's chats, decks and cards alone" do
    other = users(:learner)
    before = [ other.conversations.count, other.decks.count, Flashcard.for_user(other).count ]

    PromptLab.seed!

    assert_equal before, [ other.conversations.count, other.decks.count, Flashcard.for_user(other).count ]
  end

  # --- running ----------------------------------------------------------------

  test "a run reports each case's cards" do
    PromptLab.seed!
    stub_request(:post, llm_url).to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
      "candidates" => [{ "content" => { "parts" => [{ "text" => { flashcards: [{ question: "日", answer: "sun / day" }] }.to_json }] } }]
    }.to_json)

    report = quietly { PromptLab.run(only: "kanji", pause: 0) }

    assert_includes report, "## Kanji: the days of the week"
    assert_includes report, "| 日 | sun / day |"
  end

  # "High demand" is Gemini short of capacity for everyone: every case after
  # it would spend a request on the same refusal.
  test "a run stops at the first overloaded reply and lists what did not run" do
    PromptLab.seed!
    stub_request(:post, llm_url).to_return(status: 503, body: { error: { message: "high demand" } }.to_json)

    report = quietly { PromptLab.run(pause: 0) }

    assert_requested :post, llm_url, times: 1
    assert_includes report, "Stopped: Gemini is overloaded"
    PromptLab::CASES.each { |kase| assert_includes report, "- #{kase[:title]}" }
  end

  test "any other failure is that case's alone, and the run carries on" do
    PromptLab.seed!
    stub_request(:post, llm_url).to_return(status: 400, body: { error: { message: "bad request" } }.to_json)

    report = quietly { PromptLab.run(only: "poem", pause: 0) }

    assert_requested :post, llm_url, times: 2
    assert_equal 2, report.scan("Failed:").size
    assert_not_includes report, "Stopped"
  end

  private

  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

  # The run prints its progress to stderr.
  def quietly(&)
    result = nil
    capture_io { result = yield }
    result
  end
end
