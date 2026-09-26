# See lib/prompt_lab.rb.
namespace :prompt_lab do
  desc "Create or refresh lab@mail.com and its test chats (touches no other user)"
  task seed: :environment do
    abort "prompt_lab is for development, not #{Rails.env}" if Rails.env.production?

    learner = PromptLab.seed!
    puts "Seeded #{learner.email} / #{PromptLab::PASSWORD}: " \
         "#{learner.conversations.count} chats, #{Flashcard.for_user(learner).count} cards"
  end

  desc "Generate cards for each lab chat and write a report (one Gemini request per chat; ONLY=title filters)"
  task run: :environment do
    abort "prompt_lab is for development, not #{Rails.env}" if Rails.env.production?

    report = PromptLab.run(only: ENV.fetch("ONLY", nil))
    path = Rails.root.join("tmp/prompt_lab/#{Time.current.strftime('%Y%m%d-%H%M%S')}.md")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, report)

    puts report
    puts "\nSaved to #{path.relative_path_from(Rails.root)}"
  end
end
