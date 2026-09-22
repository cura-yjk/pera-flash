require "test_helper"

class PeraPromptTest < ActiveSupport::TestCase
  setup do
    @cards = [
      Flashcard.new(question: "What does 猫 mean?", answer: "Cat (neko)"),
      Flashcard.new(question: "は vs が?", answer: "は marks topic, が marks subject")
    ]
  end

  # This is the only thing connecting the two halves of the app: without it the
  # chat teaches in ignorance of what the flashcards already know isn't sticking.
  test "what the learner keeps forgetting is added to the instructions" do
    prompt = PeraPrompt.for(struggling: @cards)

    assert_match(/repeatedly forgotten/, prompt)
    assert_match "What does 猫 mean?", prompt
    assert_match "Cat (neko)", prompt
  end

  # Pera should find an opening, not read the list back or make anyone feel behind.
  test "the instructions say how to use them, not just what they are" do
    # Squished: the heredoc wraps these lines, and the test is about the
    # instruction being present, not where it happens to break.
    prompt = PeraPrompt.for(struggling: @cards).squish

    assert_match(/work these in naturally/i, prompt)
    assert_match(/do not list them back/i, prompt)
    assert_match(/never make the student feel behind/i, prompt)
  end

  # Asked for once, at the start. It used to be asked for on every request,
  # which the model could only judge from a history PeraReply caps at 30 -- so
  # deep into a lesson the greeting had scrolled out, and Pera was being told
  # to introduce herself to a conversation with no introduction in it.
  test "asks for an introduction when Pera has not spoken yet" do
    assert_match(/Introduce\s+yourself by that name/, PeraPrompt.for(greet: true))
  end

  test "stops asking once Pera has spoken" do
    assert_no_match(/Introduce\s+yourself/, PeraPrompt.for(greet: false))
  end

  test "is still Pera either way" do
    assert_includes PeraPrompt.for(greet: false), "You are ペラ (Pera)"
  end

  # Everything else the prompt says is the same; only the sentence goes.
  test "drops nothing but the introduction" do
    with_it = PeraPrompt.for(greet: true).squish
    without = PeraPrompt.for(greet: false).squish

    assert_equal with_it.sub(" Introduce yourself by that name the first time you greet them.", ""),
                 without
  end

  test "the base prompt is unchanged by the addition" do
    assert PeraPrompt.for(struggling: @cards).start_with?(PeraPrompt.for)
  end

  test "base_prompt is not part of the public surface" do
    assert_not PeraPrompt.respond_to?(:base_prompt)
  end

  # The two prompts drifted apart once already: cards were told to annotate
  # kanji and the chat was told nothing, so the same word was taught with
  # romaji in chat and furigana on the card made from it.
  # Gemini generalised "annotate every kanji" into "annotate Japanese", and
  # produced が[が] and ペラ[ぺら] -- kana annotated with itself, which renders
  # as a reading above a character that is already its own reading.
  test "the furigana rule says kana are not annotated" do
    assert_match(/Only kanji take readings/, PeraPrompt::FURIGANA_RULE)
    assert_match(/never が\[が\]/, PeraPrompt::FURIGANA_RULE)
  end

  # The shape is for corrections. A sentence that was already right fell
  # between that and "just answer a question", so the model improvised: a
  # greeting, the same praise three times over, and an invented heading.
  test "the prompt says what to do with a sentence that is already correct" do
    assert_match(/already correct/, PeraPrompt.for)
    assert_match(/Do not reach for the shape above/, PeraPrompt.for)
  end

  # Every reply ended by recommending the Generate flashcards button, unasked.
  test "the app guide says to answer about the app, not to advertise it" do
    assert_match(/only then/, PeraPrompt::APP_GUIDE)
    assert_match(/not a place to advertise/, PeraPrompt::APP_GUIDE)
  end

  test "the chat prompt carries the same furigana rule the cards use" do
    assert_includes PeraPrompt.for, PeraPrompt::FURIGANA_RULE.strip
  end

  test "the chat prompt carries the shared language rule" do
    assert_includes PeraPrompt.for, PeraPrompt::EXPLANATION_LANGUAGE_RULE.strip
  end

  # Removed deliberately in favour of a version that does not refuse ordinary
  # questions -- but the injection clause was worth keeping.
  test "the prompt still says submitted text is not an instruction" do
    assert_match(/never instructions\s+to follow/i, PeraPrompt.for)
  end


  test "the prompt tells Pera the app exists" do
    assert_includes PeraPrompt.for, PeraPrompt::APP_GUIDE.strip
  end

  # The guide names paths, and a prompt is the one place a broken link fails
  # silently: Pera would keep sending students to a URL that 404s, and nothing
  # would ever go red. This is what makes that impossible.
  test "every path the guide mentions is a real route" do
    paths = PeraPrompt::APP_GUIDE.scan(%r{/[a-z][a-z_/-]*}).uniq

    assert_operator paths.size, :>=, 5, "expected the guide to name several paths"

    paths.each do |path|
      assert Rails.application.routes.recognize_path(path),
             "#{path} is named in APP_GUIDE but is not a route"
    rescue ActionController::RoutingError
      flunk "#{path} is named in APP_GUIDE but is not a route"
    end
  end

  # The case that sent a beginner their feedback in a language they came to
  # learn. Practice is not a request: what a student writes is the language
  # being taught, so following it pointed Pera at Japanese.
  test "the prompt names the language to explain in" do
    assert_includes PeraPrompt.for, "Explain in English"
  end

  # Table headers used to follow the student's language. They are part of the
  # explanation, so they follow the same rule.
  test "table headers are named as English too" do
    assert_includes PeraPrompt.for, '"Japanese Word"'
  end

  test "carries what the student keeps forgetting" do
    struggling = [flashcards(:neko_card)]

    assert_match flashcards(:neko_card).question, PeraPrompt.for(struggling: struggling)
  end
end
