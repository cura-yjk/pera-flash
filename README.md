# 🃏 Pera Flash

Pera Flash is a Japanese tutor you chat with. Write a sentence at whatever level you're at and
ペラ (Pera) corrects it and explains the grammar — then any correction can become a flashcard,
reviewed on a spaced-repetition schedule until it sticks.

_DROP SCREENSHOT HERE_
<br>
App home: https://pera-flash-3683e7b80a56.herokuapp.com/

## What it does

**Chatting**
- Write Japanese at whatever level you're at; Pera corrects it and explains why, in English
- Replies stream in as they're generated rather than landing all at once
- Pera is reminded of the recent conversation *and* of the cards you keep getting wrong, so the
  tutoring stays pointed at your actual weak spots
- Every kanji is annotated with its reading as furigana — switch them off when you want to test
  yourself
- Each chat is named after the first thing you say, can be renamed from its title, and is kept so
  you can go back to it
- When Gemini is busy or out of quota, Pera says which, and a **Try again** button picks the reply
  back up without resending your message

**Flashcards**
- Turn any conversation into cards: they stream in one at a time as Pera writes them, with the
  Japanese on the front, and you can edit any of them before saving
- Only what was said since the last batch is carded, and a card you already have is marked and
  skipped rather than saved twice
- Organise them into decks, search across them as you type, edit or delete any of them
- Export a deck as CSV, with the headers Anki expects

**Studying**
- Review on a spaced-repetition schedule — grade a card *again*, *good* or *easy* and it comes back
  when you're about to forget it, not before
- Quiz yourself multiple-choice, with the wrong answers drawn from your own other cards so they're
  plausibly confusable
- Study everything at once, or one deck at a time

**Elsewhere**
- Installs to a phone's home screen as a PWA

## Getting Started
### Setup

Needs Ruby 3.3.5 and PostgreSQL.

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

### Install and run
```
bin/setup
```
This installs gems, prepares the database and starts the server (`bin/setup --skip-server` stops
short of that; `bin/dev` starts it later).

For sample data, `bin/rails db:seed` — but note it **deletes every user** first, so don't run it
against a database whose accounts you want to keep.

### Tests
```
bin/rails test          # models, controllers, services
bin/rails test:system   # in a real browser (Chrome; BROWSER=firefox for Firefox)
bin/ci                  # everything CI runs: lint, security scans, tests
```
The test suite never calls Gemini, so it needs no key.

## Built With
- [Rails 8](https://guides.rubyonrails.org/) - Backend / Front-end
- [Hotwire](https://hotwired.dev/) (Turbo + Stimulus) - Front-end JS
- [Heroku](https://heroku.com/) - Deployment
- [PostgreSQL](https://www.postgresql.org/) - Database
- [Bootstrap](https://getbootstrap.com/) — Styling
- [RubyLLM](https://rubyllm.com/) + [Gemini](https://ai.google.dev/) — Chat tutor and structured flashcard generation

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
