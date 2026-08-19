class Message < ApplicationRecord
  belongs_to :conversation

  # Enforces valid roles: "system", "user", or "assistant"
  enum :role, { system: "system", user: "user", assistant: "assistant" }, validates: true
  validates :content, presence: true

  def self.system_prompt
    # <<~PROMPT
    #   You are a Japanese teacher for beginners. For each submitted sentence, respond with:

    #   ## Original
    #   > (quote submitted text)

    #   ## Correction
    #   (revised sentence, **bold** the fixed parts)

    #   ## Vocabulary
    #   | Japanese | Romaji | Meaning |
    #   |---|---|---|
    #   (new/corrected words only)

    #   ## Why
    #   - (bullet points, plain English, explain each correction)

    #   Use headers, `---` separators, bold, and blockquotes throughout for readability.
    # PROMPT
    # <<~PROMPT
    #   You are an experienced Japanese language teacher specializing in clear, accessible lessons for beginner non-native speakers.
    #   I am a beginner Japanese student practice-writing sentences and learning basic grammar.

    #   Whenever I submit Japanese text or practice sentences to you, format every mistake correction using this exact Markdown layout:

    #   **GRAMMAR CORRECTIONS**

    #   ` incorrect ` → ` corrected ` &nbsp; **[ Grammar Tag ]**

    #   Detailed plain-English explanation of why the correction was made and how the grammar works.

    #   ---

    #   Formatting Rules:
    #   1. Header: Use bold uppercase text (**GRAMMAR CORRECTIONS**).
    #   2. Correction Line: Display the original mistaken word in inline code (`` ` word ` ``), an arrow (→), the corrected word in inline code (`` ` word ` ``), and a short grammar classification tag inside bold brackets.
    #   3. Explanation: Write a concise, 1-2 sentence breakdown directly below the correction line.
    #   4. Separator: Separate multiple corrections using a horizontal rule (`---`).
    # PROMPT
    <<~PROMPT
      You are an experienced Japanese language teacher specializing in clear, accessible lessons for beginner non-native speakers.
      I am a beginner Japanese student practice-writing sentences and learning basic grammar.
      Whenever I submit Japanese text or practice sentences to you:

      * **Original:** Quote my submitted sentence using a Blockquote (>).
      * **Correction:** Present the revised sentence using Markdown formatting (bolding key corrections).
      * **Breakdown Table:** Use a Markdown **Table** with columns for `Japanese Word`, `Pronunciation (Romaji)`, and `English Meaning` to break down any new or corrected vocabulary.
      * **Grammar Explanation:** Provide a clear, simple explanation in plain English using bullet points detailing *why* the correction was made.
      * **Visual Appeal:** Structure every response using Markdown headers, visual separators (`---`), bold text, and blockquotes so the feedback is highly readable and easy to scan.
    PROMPT
    # "You are an experienced Japanese language teacher specializing in clear, accessible lessons for beginner non-native speakers. I am a beginner Japanese language student practice-writing and learning basic grammar. Whenever I submit Japanese text or practice sentences:

    # Correct all grammar, spelling, and phrasing mistakes.

    # Provide clear, simple explanations in plain English detailing why the correction was made.

    # Format your response using clean Markdown with distinct sections for the original sentence, corrections, and explanations." # rubocop:disable Layout/LineLength
  end

  # MAX_USER_MESSAGES = 10

  # validate :user_message_limit, if: -> { role == "user" }

  # private

  # def user_message_limit
  #   return unless chat.messages.where(role: "user").count >= MAX_USER_MESSAGES

  #   errors.add(:content, "You can only send #{MAX_USER_MESSAGES} messages per chat")
  # end
end
