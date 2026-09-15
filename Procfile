# Runs before each release. Without it nothing applies migrations on deploy:
# this is a buildpack app, so there is no entrypoint doing it, and every
# migration has had to be run by hand. A failing release aborts the deploy
# rather than leaving the app serving against a stale schema.
release: bin/rails db:migrate

# Identical to the command Heroku already runs by default for this app, so
# adding this file changes nothing about how the web process starts -- only
# that the release phase above now exists.
web: bin/rails server -p ${PORT:-5000} -e $RAILS_ENV
