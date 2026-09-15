require "test_helper"

# Every locale has to carry the same keys as English.
#
# A missing key does not raise: with fallbacks on it quietly shows English, and
# without them it renders "translation missing: ko.decks.index.title" to a
# learner. Neither announces itself, so a translation can rot for months after
# someone adds a key to a view. This is what notices.
#
# Compares the app's own files rather than the loaded backend, which also holds
# date formats, Devise and simple_form strings that ship with their gems.
class LocaleCoverageTest < ActiveSupport::TestCase
  PLURAL_FORMS = %w[zero one two few many other].freeze

  ENGLISH = YAML.load_file(Rails.root.join("config/locales/en.yml")).fetch("en").freeze

  (I18n.available_locales.map(&:to_s) - ["en"]).each do |locale|
    test "#{locale} covers every key English has" do
      missing = missing_keys(ENGLISH, translations(locale), [])

      assert_empty missing, "#{locale} is missing: #{missing.join(', ')}"
    end

    test "#{locale} has no keys English does not" do
      extra = missing_keys(translations(locale), ENGLISH, [])

      assert_empty extra, "#{locale} has keys English does not: #{extra.join(', ')}"
    end

    # A translation that drops %{name} silently loses the learner's name; one
    # that invents %{nmae} raises at render time.
    test "#{locale} uses the same interpolations as English" do
      mismatched = interpolation_mismatches(ENGLISH, translations(locale), [])

      assert_empty mismatched, "#{locale}: #{mismatched.join('; ')}"
    end
  end

  private

  def translations(locale)
    YAML.load_file(Rails.root.join("config/locales/#{locale}.yml")).fetch(locale)
  end

  def missing_keys(reference, subject, path)
    # Japanese, Korean and Chinese have one plural form where English has two,
    # so a count only has to offer "other" to be complete.
    return plural_gap(subject, path) if plural?(reference)

    reference.flat_map do |key, value|
      here = path + [key]
      next [here.join(".")] unless subject.is_a?(Hash) && subject.key?(key)
      next missing_keys(value, subject[key], here) if value.is_a?(Hash)

      []
    end
  end

  def plural?(value)
    value.is_a?(Hash) && value.keys.all? { |key| PLURAL_FORMS.include?(key.to_s) }
  end

  def plural_gap(subject, path)
    subject.is_a?(Hash) && subject.key?("other") ? [] : ["#{path.join('.')}.other"]
  end

  def interpolation_mismatches(reference, subject, path)
    reference.flat_map do |key, value|
      here = path + [key]
      next [] unless subject.is_a?(Hash) && subject.key?(key)
      next interpolation_mismatches(value, subject[key], here) if value.is_a?(Hash) && !plural?(value)
      next [] unless value.is_a?(String) && subject[key].is_a?(String)

      expected = value.scan(/%\{(\w+)\}/).flatten.sort
      actual = subject[key].scan(/%\{(\w+)\}/).flatten.sort
      expected == actual ? [] : ["#{here.join('.')} expects #{expected.inspect}, has #{actual.inspect}"]
    end
  end
end
