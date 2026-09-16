# 🃏 Pera Flash

Pera Flash is a Japanese-learning chatbot. Chat with ペラ (Pera), an AI tutor who corrects your
Japanese sentences and explains the grammar, then turn any conversation into a set of flashcards
you can organize into decks, search, and export.

_DROP SCREENSHOT HERE_
<br>
App home: https://pera-flash-3683e7b80a56.herokuapp.com/

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
