puts("clearing DB...")
Flashcard.destroy_all       # references conversations + decks → first
Message.destroy_all         # references conversations
Conversation.destroy_all    # references users
Deck.destroy_all            # references users
User.destroy_all            # parents last

User.create!(email: "admin@mail.com", name: "admin", password: "qwerty")
user = User.create!(email: "matt@mail.com", name: "Matt", password: "qwerty")
deck = Deck.create!(user: user, name: "Japanese Basic")

flashcards_data = [
  { question: "How do you say 'I am a student' politely?",
    answer: "わたしは がくせい です。(Watashi wa gakusei desu.)" },
  { question: "What does the particle は (wa) do?",
    answer: "It marks the topic of the sentence." },
  { question: "What does です (desu) add to a sentence?",
    answer: "It makes the sentence polite — similar to 'am/is/are'." },
  { question: "How do you say 'This is a book'?",
    answer: "これは ほん です。(Kore wa hon desu.)" },
  { question: "What does the particle を (o) mark?",
    answer: "The direct object of a verb." },
  { question: "Why is こんにちは useful when speaking Japanese?",
    answer: "It's a polite, natural daytime greeting." },
  { question: "How do you say 'I like cats'?",
    answer: "ねこが すき です。(Neko ga suki desu.)" },
  { question: "What's the difference between は and が?",
    answer: "は marks the topic; が marks the subject, often for new or emphasized information." }
]

flashcards_data.each do |data|
  deck.flashcards.create!(question: data[:question], answer: data[:answer])
end

puts "Created deck \"#{deck.name}\" with #{deck.flashcards.count} flashcards"
puts("Succesfully created #{User.count} accounts...")
