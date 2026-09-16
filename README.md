# 🃏 Pera Flash

Pera Flash is a Japanese tutor you chat with. Write a sentence at whatever level you're at and
ペラ (Pera) corrects it and explains the grammar — then any correction can become a flashcard,
reviewed on a spaced-repetition schedule until it sticks.

_DROP SCREENSHOT HERE_
<br>
App home: https://pera-flash-3683e7b80a56.herokuapp.com/

## What it does

**Chatting**
- Write Japanese at whatever level you're at; Pera corrects it and explains why, in your language
- Replies stream in as they're generated rather than landing all at once
- Pera is reminded of the recent conversation *and* of the cards you keep getting wrong, so the
  tutoring stays pointed at your actual weak spots
- Every kanji is annotated with its reading as furigana — switch them off when you want to test
  yourself
- Conversations are titled automatically and kept, so you can go back to one

**Flashcards**
- Turn any conversation into cards; a correction becomes a question and an answer
- Organise them into decks, search across them as you type, edit or delete any of them
- Export a deck as CSV, with the headers Anki expects

**Studying**
- Review on a spaced-repetition schedule — grade a card *again*, *good* or *easy* and it comes back
  when you're about to forget it, not before
- Quiz yourself multiple-choice, with the wrong answers drawn from your own other cards so they're
  plausibly confusable
- Study everything at once, or one deck at a time

**Elsewhere**
- Interface in six languages: English, 日本語, 한국어, 简体中文, 繁體中文 and Deutsch
- Installs to a phone's home screen as a PWA

## Getting Started
### Setup

Install gems
```
bundle install
```

### ENV Variables
Create `.env` file
```
touch .env
```
Inside `.env`, set these variables. For any API keys, see group Slack channel.
```
GEMINI_API_KEYS=your_gemini_api_key
```
`GEMINI_API_KEYS` takes a comma-separated list — Pera falls through to the next key when one
runs out of quota. A single key is fine. `GEMINI_API_KEY` (singular) is still read as a fallback.

### DB Setup
```
rails db:create
rails db:migrate
rails db:seed
```

### Run a server
```
rails s
```
(or `bin/dev`, which this repo also has set up as a shortcut for the same thing)

## Built With
- [Rails 8](https://guides.rubyonrails.org/) - Backend / Front-end
- [Stimulus JS](https://stimulus.hotwired.dev/) - Front-end JS
- [Heroku](https://heroku.com/) - Deployment
- [PostgreSQL](https://www.postgresql.org/) - Database
- [Bootstrap](https://getbootstrap.com/) — Styling
- [RubyLLM](https://rubyllm.com/) + [Gemini](https://ai.google.dev/) — Chat tutor, conversation titling and structured flashcard generation

## Acknowledgements

Pera Flash grew out of a simple idea: the hardest part of learning a language isn't having a
conversation, it's remembering what you learned from it. Pera turns every correction and every new
word from a chat into something you can actually review again.

## Team Members
- [Matthew Hardcastle](https://www.linkedin.com/in/matthew-hardcastle-7762123aa/)
- [Twinky Hung](https://www.linkedin.com/in/twinky-hung/)
- [Yusuke Kamihanawa](https://www.linkedin.com/in/cura-yjk/)

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License
This project is licensed under the MIT License
