# A fixed set of chats to try the flashcard prompt against, so a change to
# FlashcardGeneration#prompt can be judged on the same input every time rather
# than on whichever chat happened to be open.
#
# Each case is one kind of material the prompt has to handle, with what a good
# result looks like. The chats are written the way Pera actually answers --
# the Original / Correction / Breakdown / Why shape for sentences to check,
# plain answers for questions -- because the seeded demo chats in db/seeds.rb
# are a few lines each, and real replies run to thousands of characters.
#
#   bin/rails prompt_lab:seed   # (re)creates lab@mail.com and its chats; free
#   bin/rails prompt_lab:run    # generates cards for every case; one request each
#
# Seeding only ever touches lab@mail.com. db/seeds.rb starts by deleting every
# user, so it is no way to add these to a development database that holds
# chats worth keeping.
module PromptLab
  EMAIL = "lab@mail.com"
  PASSWORD = "qwerty"

  # Cards the lab learner already has, for the "overlap" case: generation is
  # never shown them, so this is where duplicates across chats would show up.
  DECK = {
    name: "Animals",
    cards: [
      ["猫[ねこ]", "cat"],
      ["好[す]き", "like / likable"],
      ["〜が好[す]きです", "to like ~ (the liked thing takes が)"]
    ]
  }.freeze

  CASES = [
    {
      title: "Corrections: a weekend with a friend",
      expect: "Cards from the learner's own mistakes: と (with) rather than に, and " \
              "面白[おもしろ]かったです as the past of an い-adjective. The last sentence " \
              "was correct, so nothing new from it.",
      messages: [
        ["user", "昨日、友達に映画を見に行きました。"],
        ["assistant", <<~MD],
          Nice try — this is very close! Just one particle to fix.

          * **Original:**
            > 昨日、友達に映画を見に行きました。
          * **Correction:**
            > 昨日[きのう]、友達[ともだち]**と**映画[えいが]を見[み]に行[い]きました。
          * **Breakdown:**
            | Japanese Word | English Meaning |
            | :--- | :--- |
            | 昨日[きのう] | yesterday |
            | 友達[ともだち] | friend |
            | と | with (someone, doing it together) |
            | 映画[えいが] | movie |
            | 〜に行[い]く | to go (in order) to do ~ |
          * **Why:**
            * **と** marks the person you do something *together with*. With **に**, it
              sounds as if the friend is where you went, or who received the movie.
            * 見[み]に行[い]きました is perfect: the verb stem + に + 行く means "go to do".

          ---

          What did you think of the movie? Try telling me in Japanese!
        MD
        ["user", "映画はとても面白いでした。"],
        ["assistant", <<~MD],
          Almost! い-adjectives change their own ending for the past tense.

          * **Original:**
            > 映画はとても面白いでした。
          * **Correction:**
            > 映画[えいが]はとても**面白[おもしろ]かったです**。
          * **Breakdown:**
            | Japanese Word | English Meaning |
            | :--- | :--- |
            | とても | very |
            | 面白[おもしろ]い | interesting / fun |
            | 面白[おもしろ]かった | was interesting (past) |
          * **Why:**
            * For an い-adjective, drop the final い and add **かった** for the past:
              面白い → 面白かった. Then add です to keep it polite.
            * **いでした** is a very common mistake — でした is the past of です, and it is
              used after nouns and な-adjectives, not い-adjectives.
        MD
        ["user", "次は一緒にラーメンを食べたいです。"],
        ["assistant", "Perfect! 一緒[いっしょ]に (together) and 〜たいです (want to ~) are both exactly right. " \
                      "次[つぎ]は ラーメンですね！ 🍜"]
      ]
    },
    {
      title: "Vocabulary: talking about the weather",
      expect: "One card per weather word (晴[は]れ, 雨[あめ], 雪[ゆき], 曇[くも]り, 暑[あつ]い, " \
              "寒[さむ]い), and perhaps 今日[きょう]は〜です as a pattern.",
      messages: [
        ["user", "How do I talk about the weather in Japanese?"],
        ["assistant", <<~MD],
          Weather is a great first topic — it comes up in almost every conversation in Japan!

          ### Weather words

          | Japanese Word | English Meaning |
          | :--- | :--- |
          | 天気[てんき] | weather |
          | 晴[は]れ | sunny / clear |
          | 雨[あめ] | rain |
          | 雪[ゆき] | snow |
          | 曇[くも]り | cloudy |

          ### How it feels

          | Japanese Word | English Meaning |
          | :--- | :--- |
          | 暑[あつ]い | hot (weather) |
          | 寒[さむ]い | cold (weather) |

          ---

          The simplest pattern is **今日[きょう]は〜です** ("today is ~"):

          * 今日[きょう]は 晴[は]れです。 — It's sunny today.
          * 今日[きょう]は 雨[あめ]です。 — It's rainy today.
        MD
        ["user", "How do I say it's hot today?"],
        ["assistant", <<~MD]
          **今日[きょう]は 暑[あつ]いです。**

          暑[あつ]い is an い-adjective, so it goes straight before です. People also often say
          **暑[あつ]いですね**, adding ね to invite agreement: "It's hot, isn't it?"
        MD
      ]
    },
    {
      title: "Grammar: 〜てしまう",
      expect: "A card for 〜てしまう (completion, and regret) and one for its casual form " \
              "〜ちゃう. Not a card per example sentence.",
      messages: [
        ["user", "What does しまいました mean in 財布を忘れてしまいました?"],
        ["assistant", <<~MD],
          Good question — **〜てしまう** is one of the most useful patterns in everyday Japanese.

          ### 〜てしまう

          Take the て-form of a verb and add しまう. It adds one of two feelings:

          1. **Regret** — something happened that you didn't want.
             * 財布[さいふ]を忘[わす]れてしまいました。 — I (annoyingly) forgot my wallet.
          2. **Completely done** — the action is finished, all of it.
             * ケーキを全部[ぜんぶ]食[た]べてしまいました。 — I ate the whole cake.

          ---

          | Japanese Word | English Meaning |
          | :--- | :--- |
          | 財布[さいふ] | wallet |
          | 忘[わす]れる | to forget |
          | 全部[ぜんぶ] | all / the whole thing |

          Often both feelings are there at once: eating the *whole* cake is usually also a
          bit of a regret!
        MD
        ["user", "My friend said 食べちゃった. Is that the same?"],
        ["assistant", <<~MD]
          Yes! **〜ちゃう** is the casual, spoken form of **〜てしまう**:

          * 食[た]べてしまった → **食[た]べちゃった**
          * 忘[わす]れてしまった → **忘[わす]れちゃった**

          Use it with friends. In polite speech, keep 〜てしまいました.
        MD
      ]
    },
    {
      title: "Kanji: the days of the week",
      expect: "One card per kanji — 日, 月, 火, 水, 木, 金, 土 — each with its meaning. Watch " \
              "whether the front gives the reading away: furigana on a card that tests the " \
              "reading is the answer printed on the question.",
      messages: [
        ["user", "What are the kanji for the days of the week?"],
        ["assistant", <<~MD],
          Each day of the week is named after a kanji, and each kanji is a natural element.
          Learn these seven and you can read every day of the week!

          | Kanji | Meaning | Day |
          | :--- | :--- | :--- |
          | 日[にち] | sun / day | 日曜日[にちようび] — Sunday |
          | 月[げつ] | moon / month | 月曜日[げつようび] — Monday |
          | 火[か] | fire | 火曜日[かようび] — Tuesday |
          | 水[すい] | water | 水曜日[すいようび] — Wednesday |
          | 木[もく] | tree / wood | 木曜日[もくようび] — Thursday |
          | 金[きん] | gold / money | 金曜日[きんようび] — Friday |
          | 土[ど] | earth / soil | 土曜日[どようび] — Saturday |

          ---

          Every day ends in **曜日[ようび]**, "day of the week". So 今日[きょう]は 何曜日[なんようび]ですか？
          means "What day of the week is it today?"
        MD
        ["user", "Why is 日 read にち in 日曜日 but ひ in other words?"],
        ["assistant", <<~MD]
          Great catch! Most kanji have two kinds of reading:

          * **On'yomi (音読[おんよ]み)** — the reading borrowed from Chinese. Mostly used when
            kanji are combined into words: 日曜日[にちようび], 毎日[まいにち] (every day).
          * **Kun'yomi (訓読[くんよ]み)** — the native Japanese reading. Mostly used when a kanji
            stands alone: 日[ひ] (sun, day), 水[みず] (water), 木[き] (tree).

          | Kanji | On'yomi | Kun'yomi |
          | :--- | :--- | :--- |
          | 日 | にち | ひ |
          | 水 | すい | みず |
          | 木 | もく | き |

          You don't need to memorise the rule — just learn each word with its reading, and the
          patterns will start to feel natural.
        MD
      ]
    },
    {
      title: "Poem: Bashō's old pond",
      expect: "Beginner-useful cards from the poem — 古[ふる]い / 池[いけ], 飛[と]び込[こ]む, " \
              "水[みず]の音[おと] — and a note that 蛙[かわず] is poetic (かえる in everyday speech). " \
              "Not the whole poem as one card, and not や taught as 'and'.",
      messages: [
        ["user", "My friend showed me this poem: 古池や 蛙飛び込む 水の音. What does it mean?"],
        ["assistant", <<~MD],
          This is one of the most famous poems in Japanese — a haiku by Matsuo Bashō, from 1686!

          > 古池[ふるいけ]や　蛙[かわず]飛[と]び込[こ]む　水[みず]の音[おと]

          *An old pond — a frog jumps in, the sound of water.*

          ### Line by line

          | Japanese Word | English Meaning |
          | :--- | :--- |
          | 古池[ふるいけ] | old pond (古[ふる]い old + 池[いけ] pond) |
          | や | a poetic pause, like "ah…" — a "cutting word" (切[き]れ字[じ]) |
          | 蛙[かわず] | frog (old, poetic reading) |
          | 飛[と]び込[こ]む | to jump in / dive in |
          | 水[みず]の音[おと] | the sound of water |

          ---

          A haiku has **5-7-5** sounds: ふるいけや (5) / かわずとびこむ (7) / みずのおと (5).

          The や here is **not** the や that means "and" in lists (りんごやバナナ). In poetry it
          marks a pause for feeling, like a dash.
        MD
        ["user", "Do people still say かわず for frog?"],
        ["assistant", <<~MD],
          Not in everyday speech — today a frog is **蛙[かえる]**, written with the same kanji.
          かわず survives mostly in poems and old sayings, so it's worth recognising but you
          won't need to say it.
        MD
        ["user", "Can I use 飛び込む in normal conversation?"],
        ["assistant", <<~MD]
          Yes, all the time!

          * プールに飛[と]び込[こ]みました。 — I jumped into the pool.
          * 電車[でんしゃ]に飛[と]び込[こ]む — to rush onto a train (just as the doors close)

          The place you jump *into* takes **に**.
        MD
      ]
    },
    {
      title: "Poem: 雨ニモマケズ",
      expect: "Cards for 負[ま]けない / 負[ま]けず (not lose to) and 〜にも (even to ~), with the " \
              "modern hiragana forms rather than the old katakana spelling on the front.",
      messages: [
        ["user", "I saw 雨ニモマケズ 風ニモマケズ on a poster. Why is it in katakana?"],
        ["assistant", <<~MD]
          That's the opening of a much-loved poem by Miyazawa Kenji, written in 1931. It is in
          katakana because it was written in an older style — in his time, katakana was often
          used for writing in notebooks and official documents.

          In today's spelling it would be:

          > 雨[あめ]にも負[ま]けず　風[かぜ]にも負[ま]けず

          *Not losing to the rain, not losing to the wind.*

          | Japanese Word | English Meaning |
          | :--- | :--- |
          | 雨[あめ] | rain |
          | 風[かぜ] | wind |
          | 〜にも | even to ~ / to ~ too |
          | 負[ま]ける | to lose (to ~) — the thing you lose to takes に |
          | 負[ま]けず | without losing — an older form of 負[ま]けないで |

          ---

          You will still hear **〜ず** in modern Japanese in set phrases, like 相変[あいか]わらず
          ("as always", literally "without changing").
        MD
      ]
    },
    {
      title: "Nothing to card: how the app works",
      expect: "No cards. Nothing here teaches Japanese.",
      messages: [
        ["user", "How do I make flashcards?"],
        ["assistant", "Tap **Generate flashcards** below our chat, and I'll turn what we've " \
                      "talked about into cards. You can edit them before saving, then study " \
                      "them in [Review](/review) or [Quiz](/quiz)."],
        ["user", "Thanks!"],
        ["assistant", "You're welcome! Whenever you're ready, try writing a sentence in Japanese " \
                      "and I'll check it for you."]
      ]
    },
    {
      title: "Overlap: cats again, and dogs",
      expect: "New: 犬[いぬ] and も (also). Already in the Animals deck: 猫[ねこ], 好[す]き, " \
              "〜が好[す]きです — generation is not told that, so cards for them here are the " \
              "duplicates a save-time check would catch.",
      messages: [
        ["user", "ねこがすきです。いぬもすきです。"],
        ["assistant", <<~MD]
          すばらしいです！ Both sentences are correct.

          * **Original:**
            > ねこがすきです。いぬもすきです。
          * **Correction:**
            > **猫[ねこ]**が**好[す]**きです。**犬[いぬ]**も**好[す]**きです。
          * **Breakdown:**
            | Japanese Word | English Meaning |
            | :--- | :--- |
            | 猫[ねこ] | cat |
            | 犬[いぬ] | dog |
            | 好[す]き | like / likable |
            | も | also / too (replaces が) |
          * **Why:**
            * I only changed the hiragana into kanji so you can practise reading them.
            * **も** means "also", and it *replaces* が — so it's 犬[いぬ]**も**, never 犬がも.
        MD
      ]
    },
    {
      title: "Long chat: a day in my life",
      expect: "Only the newest 20 messages are sent, so the first two exchanges -- " \
              "朝[あさ]ごはん and 起[お]きる -- should not appear. Cards for the rest: " \
              "浴[あ]びる, 出[で]る, 電車[でんしゃ], 会議[かいぎ], 帰[かえ]る, 寝[ね]る, 忙[いそが]しい…",
      messages: [
        ["毎朝、朝ごはんを食べます。", "Perfect! 朝[あさ]ごはん is breakfast — literally \"morning rice\"."],
        ["六時に起きます。", "Correct! 起[お]きる means to wake up, or to get up."],
        ["七時にシャワーをあびます。", "Correct! シャワーを浴[あ]びる is \"to take a shower\" — 浴びる is to pour over yourself."],
        ["八時に家をでます。", "Right! 家[いえ]を出[で]る is \"to leave the house\". を marks the place you leave."],
        ["電車で会社に行きます。", "Good! 電車[でんしゃ] is train, and で marks how you travel."],
        ["十二時に昼ごはんを食べます。", "Correct! 昼[ひる]ごはん is lunch."],
        ["午後はかいぎがあります。", "Correct! 会議[かいぎ] is a meeting, and があります means \"there is\"."],
        ["六時に家にかえります。", "Right! 帰[かえ]る means to go home. に marks where you are going."],
        ["晩ごはんをつくります。", "Good! 晩[ばん]ごはん is dinner, and 作[つく]る is to make."],
        ["テレビを見ます。", "Correct! 見[み]る is to watch, as well as to see."],
        ["十一時にねます。", "Correct! 寝[ね]る is to go to bed, or to sleep."],
        ["毎日いそがしいです。", "Perfect — 忙[いそが]しい means busy. You've described your whole day in Japanese!"]
      ].flat_map { |user, assistant| [["user", user], ["assistant", assistant]] }
    }
  ].freeze

  module_function

  def user
    User.find_by(email: EMAIL)
  end

  # Replaces the lab learner's chats and cards with the cases above.
  def seed!
    learner = User.find_or_create_by!(email: EMAIL) do |u|
      u.name = "Lab"
      u.password = PASSWORD
    end

    clear(learner)
    seed_deck(learner)
    CASES.each { |kase| seed_case(learner, kase) }
    learner
  end

  def clear(learner)
    Flashcard.for_user(learner).destroy_all
    learner.conversations.destroy_all
    learner.decks.destroy_all
  end

  def seed_deck(learner)
    deck = learner.decks.create!(name: DECK[:name])
    DECK[:cards].each { |question, answer| deck.flashcards.create!(question: question, answer: answer) }
  end

  # A second apart, oldest first: messages are ordered by created_at, and rows
  # written in the same instant would tie.
  def seed_case(learner, kase)
    conversation = learner.conversations.create!(title: kase[:title])
    started = 1.day.ago
    kase[:messages].each_with_index do |(role, content), i|
      conversation.messages.create!(role: role, content: content, created_at: started + i.seconds)
    end
  end

  # Seconds between cases. Not for the per-minute quota -- nine requests are
  # well inside it -- but so a run is not nine requests in a burst on a day
  # Gemini is short of capacity.
  PAUSE = 15

  # Generates cards for every case, or the ones whose title contains only,
  # and returns the report as markdown. Each case is one real request.
  def run(only: nil, pause: PAUSE)
    learner = user or raise "No lab learner yet: run bin/rails prompt_lab:seed first"

    conversations = learner.conversations.order(:created_at).to_a
    conversations.select! { |c| c.title.downcase.include?(only.downcase) } if only.present?

    ([header] + sections(conversations, pause)).join("\n")
  end

  # Stops at the first "high demand" 503: that is Gemini short of capacity for
  # everyone, and the cases after it would only spend requests on the same
  # refusal. Other failures are one case's problem, reported in its section.
  def sections(conversations, pause)
    conversations.each_with_index.with_object([]) do |(conversation, i), report|
      sleep(pause) if i.positive?
      warn "[#{i + 1}/#{conversations.size}] #{conversation.title}"
      report << section(conversation)
    rescue RubyLLM::ServiceUnavailableError => e
      skipped = conversations.drop(i).map { |c| "- #{c.title}" }.join("\n")
      break report << "## Stopped: Gemini is overloaded\n\n#{e.message}\n\nNot run:\n\n#{skipped}\n"
    rescue StandardError => e
      report << "## #{conversation.title}\n\nFailed: #{e.class}: #{e.message}\n"
    end
  end

  def header
    prompt = FlashcardGeneration.new(Conversation.new, []).send(:prompt)
    <<~MD
      # Prompt lab, #{Time.current.strftime('%Y-%m-%d %H:%M')}

      Commit `#{`git rev-parse --short HEAD`.strip}`, prompt `#{Digest::SHA256.hexdigest(prompt)[0, 8]}`
    MD
  end

  def section(conversation)
    messages = conversation.messages_for_flashcards
    cards, seconds = timed { FlashcardGeneration.new(conversation, messages).call }

    <<~MD
      ## #{conversation.title}

      *Expect:* #{CASES.find { |c| c[:title] == conversation.title }&.dig(:expect)}

      #{cards.size} cards in #{seconds}s, from #{messages.size} messages.

      | Front | Back |
      | :--- | :--- |
      #{cards.map { |card| "| #{cell(card.question)} | #{cell(card.answer)} |" }.join("\n")}
    MD
  end

  def timed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    [result, (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)]
  end

  def cell(text)
    text.to_s.gsub("|", "\\|").gsub("\n", "<br>")
  end
end
