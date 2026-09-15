ENV["RAILS_ENV"] ||= "test"

# Pinned before the app boots: config/initializers/ruby_llm.rb reads this at
# load time and dotenv will not overwrite an already-set variable. RubyLLM
# refuses to build a request without a key, so without this the stubs below
# would never be reached -- and it guarantees the suite can never spend a real
# credential.
ENV["GEMINI_API_KEY"] = "test-gemini-key-not-a-real-credential"
ENV["OPENAI_API_KEY"] = "test-openai-key-not-a-real-credential"

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
  end
end
