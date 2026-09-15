# Seed data shaped so every feature is visible the moment you sign in:
# cards at each stage of the review schedule, cards the learner keeps
# forgetting (which the chat reads), conversations with real transcripts, and
# a second learner whose data must never appear in the first one's screens.
#
# Deterministic and offline. bin/ci replants this in RAILS_ENV=test, so it must
# never call the LLM or depend on the clock beyond fixed offsets from now.

puts "clearing DB..."
Flashcard.destroy_all       # references conversations + decks → first
Message.destroy_all         # references conversations
Conversation.destroy_all    # references users
Deck.destroy_all            # references users
User.destroy_all            # parents last

# --- accounts ---------------------------------------------------------------

User.create!(email: "admin@mail.com", name: "admin", password: "qwerty")
matt = User.create!(email: "matt@mail.com", name: "Matt", password: "qwerty")
# A second learner with her own decks and chats. Everything the app shows Matt
# is scoped to him, and the only way to see a scoping bug is to have someone
# else's data sitting in the same tables.
yuki = User.create!(email: "yuki@mail.com", name: "Yuki", password: "qwerty")

# --- review states ----------------------------------------------------------

# Where each card sits in the SM-2 schedule. Written as attributes rather than
# by calling review! so the seeded state is exact: "due in an hour" stays that
# whether this runs today or next month.
STATES = {
  # Never studied. Sorts first in review, and keeps the queue non-empty.
  new: { review_count: 0, due_at: nil, interval_days: 0.0, ease: 2.5, lapse_count: 0 },

  # Answered before, and ready again now -- these are what the navbar badge counts.
  due: { review_count: 3, due_at: 2.hours.ago, last_reviewed_at: 4.days.ago,
         interval_days: 4.0, ease: 2.5, lapse_count: 0 },

  # Learned and scheduled out. Present so the queue is a real subset of the
  # collection rather than all of it.
  later: { review_count: 6, due_at: 6.days.from_now, last_reviewed_at: 2.days.ago,
           interval_days: 8.0, ease: 2.7, lapse_count: 0 },

  # Known well enough that the schedule pushed it out past a week, and due
  # again today. Quizzes ask this one in bare kanji -- see Flashcard#mastered?.
  mastered: { review_count: 8, due_at: 3.hours.ago, last_reviewed_at: 12.days.ago,
              interval_days: 12.0, ease: 2.8, lapse_count: 0 },

  # Forgotten repeatedly: two or more lapses is what Flashcard.struggling looks
  # for, and what the chat quietly works into its lessons.
  struggling: { review_count: 9, due_at: 1.hour.ago, last_reviewed_at: 3.days.ago,
                interval_days: 0.0, ease: 1.7, lapse_count: 3 }
}.freeze

add_card = lambda do |deck, question, answer, state, conversation = nil|
  deck.flashcards.create!(STATES.fetch(state).merge(
                            question: question, answer: answer, conversation: conversation
                          ))
end

# --- Matt's conversations ---------------------------------------------------

# Kanji carry their readings inline, Anki-style: 猫[ねこ] renders as ruby text
# and collapses back to plain kanji when readings are switched off.

particles = matt.conversations.create!(title: "は vs が, one more time")
[
  [ "user", "I keep mixing up は and が. 猫[ねこ]は すきです or 猫[ねこ]が すきです?" ],
  [ "assistant", <<~MD ],
    Both are real sentences — they just answer different questions.

    | Japanese | Reading | Meaning |
    |---|---|---|
    | 猫[ねこ]は すきです | neko wa suki desu | *As for cats*, I like them |
    | 猫[ねこ]が すきです | neko ga suki desu | It's **cats** that I like |

    ---

    - **は** sets the topic — what we are talking about.
    - **が** points at the subject, often something new or being singled out.

    Try: あなたは なにが すきですか。
  MD
  [ "user", "So が is the one that picks something out?" ],
  [ "assistant", "Exactly. Think of は as \"speaking of…\" and が as \"this one, specifically\"." ]
].each { |role, content| particles.messages.create!(role: role, content: content) }

counting = matt.conversations.create!(title: "Counting things — 枚 and 本")
[
  [ "user", "How do I count flat things like tickets?" ],
  [ "assistant", <<~MD ]
    Flat things take **枚[まい]**: きっぷ 2枚[にまい] (two tickets).

    Long thin things take **本[ほん]** instead — えんぴつ 3本[さんぼん] (three pencils).
    Watch the sound changes: 1本[いっぽん], 3本[さんぼん], 6本[ろっぽん].
  MD
].each { |role, content| counting.messages.create!(role: role, content: content) }

# Said since the last generation, so "Generate flashcards" has new material to
# work from rather than answering "you're all caught up".
restaurant = matt.conversations.create!(title: "Ordering at a restaurant")
[
  [ "user", "What do I say when I walk into a restaurant?" ],
  [ "assistant", "The staff greet you with いらっしゃいませ. You don't need to reply — 一人[ひとり]です (\"one person\") is enough." ],
  [ "user", "And to order?" ],
  [ "assistant", "Point and say これを ください (\"this one, please\"), or 〜を おねがいします for something you can name." ]
].each { |role, content| restaurant.messages.create!(role: role, content: content) }

# --- Matt's decks -----------------------------------------------------------

basics = matt.decks.create!(name: "Japanese Basics")
add_card.call(basics, "How do you say 'I am a student' politely?", "わたしは 学生[がくせい]です。", :due)
add_card.call(basics, "What does the particle は do?", "It marks the topic of the sentence.", :later)
add_card.call(basics, "What does です add to a sentence?", "It makes the sentence polite — like 'am/is/are'.", :later)
add_card.call(basics, "How do you say 'This is a book'?", "これは 本[ほん]です。", :mastered)
add_card.call(basics, "What does the particle を mark?", "The direct object of a verb.", :due)
add_card.call(basics, "How do you say 'I like cats'?", "猫[ねこ]が すきです。", :new)
# The one Matt keeps losing — and the reason the chat above keeps circling back.
add_card.call(basics, "What is the difference between は and が?",
              "は marks the topic; が marks the subject, often new or singled out.", :struggling, particles)
add_card.call(basics, "When do you use が instead of は?",
              "When pointing something out as new information, or answering 'which one?'.", :struggling, particles)

counters = matt.decks.create!(name: "Counting things")
add_card.call(counters, "Which counter do flat things take?", "枚[まい] — きっぷ 2枚[にまい] (two tickets).", :struggling, counting)
add_card.call(counters, "Which counter do long thin things take?", "本[ほん] — えんぴつ 3本[さんぼん] (three pencils).", :mastered)
add_card.call(counters, "How do you say 'one pencil'?", "えんぴつ 1本[いっぽん]。Note いっ, not いち.", :new)
add_card.call(counters, "How do you count small animals?", "匹[ひき] — 猫[ねこ] 2匹[にひき] (two cats).", :new)
add_card.call(counters, "How do you say 'three tickets'?", "きっぷ 3枚[さんまい]。", :new)

meals = matt.decks.create!(name: "At a restaurant")
add_card.call(meals, "What do staff say as you walk in?", "いらっしゃいませ。No reply is needed.", :new)
add_card.call(meals, "How do you say 'table for one'?", "一人[ひとり]です。", :new)
add_card.call(meals, "How do you order by pointing?", "これを ください。", :new)
add_card.call(meals, "How do you ask for the bill?", "お会計[かいけい]を おねがいします。", :new)

# --- Yuki's data ------------------------------------------------------------

yuki_deck = yuki.decks.create!(name: "Yuki's private deck")
yuki_chat = yuki.conversations.create!(title: "Yuki's private conversation")
yuki_chat.messages.create!(role: "user", content: "This must never show up in Matt's chat history.")
add_card.call(yuki_deck, "Does this belong to Matt?", "No — it is Yuki's, and his screens must never show it.", :due)

# --- summary ----------------------------------------------------------------

due = Flashcard.for_user(matt).due.count
puts "Created #{User.count} accounts (matt@mail.com / qwerty is the one to sign in as)"
matt.decks.each { |deck| puts "  deck: #{deck.name} — #{deck.flashcards.count} cards" }
puts "  #{matt.conversations.count} conversations, #{Message.where(conversation: matt.conversations).count} messages"
mastered = Flashcard.for_user(matt).select(&:mastered?).count
puts "  #{due} cards due now, #{Flashcard.for_user(matt).struggling.count} being forgotten repeatedly"
puts "  #{mastered} known well enough to be quizzed without readings"
