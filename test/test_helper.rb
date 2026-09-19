ENV["RAILS_ENV"] ||= "test"

# Pinned before the app boots: config/initializers/ruby_llm.rb reads this at
# load time and dotenv will not overwrite an already-set variable. RubyLLM
# refuses to build a request without a key, so without this the stubs below
# would never be reached -- and it guarantees the suite can never spend a real
# credential.
#
# Both spellings are pinned. GEMINI_API_KEYS is the one LlmChat#keys reads
# first, and it is the only one .env defines -- so pinning the singular alone
# left the suite running on the real production keys, one unstubbed request
# away from spending live quota.
ENV["GEMINI_API_KEYS"] = "test-gemini-key-not-a-real-credential"
ENV["GEMINI_API_KEY"] = "test-gemini-key-not-a-real-credential"
ENV["OPENAI_API_KEY"] = "test-openai-key-not-a-real-credential"

# Before the app boots: a file already loaded when SimpleCov starts is invisible
# to it, and config/environment pulls in most of the app.
require "simplecov"
SimpleCov.start "rails" do
  enable_coverage :branch
  add_filter "/test/"
end

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Each worker is its own process with its own coverage. Naming the result
    # per worker and writing it out on the way down lets SimpleCov merge them;
    # without this the report is whichever worker finished last.
    parallelize_setup do |worker|
      SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}"
    end

    parallelize_teardown do |_worker|
      SimpleCov.result
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
  end
end
