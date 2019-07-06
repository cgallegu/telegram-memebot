require 'telegram/bot'
require 'pp'
require 'nokogiri'
require 'open-uri'
require 'json'
require 'faraday'
require 'pry'
require 'rb-readline'
require 'digest'
require 'logger'

token = ENV['TELEGRAM_MEMEBOT_TOKEN']

def get_memes
  doc = Nokogiri::HTML(open('https://9gag.com/trending'))
  raw_memes = doc.css('script[type="application/ld+json"]')[0]
  memes = JSON.parse(raw_memes.text)['itemListElement'].map { |e| e['url'] }
  meme_id_regex = /https:\/\/9gag.com\/gag\/(.*)\/.*/
  meme_ids = memes.map { |e| e.match(meme_id_regex)[1]  }
  meme_image_urls = meme_ids.map { |e| "https://img-9gag-fun.9cache.com/photo/#{e}_460s.jpg"  }
  meme_image_urls
end

class Stats
  def initialize(file_map, logger)
    @file_map = file_map
    @logger = logger

    @stats = read() || Hash.new(0)
  end

  def read
    result = {}
    @file_map.each { |group, file_name|
      if (File.exist?(file_name))
        @logger.info("Reading stats for group #{group}: #{file_name}")
        file = File.open(file_name, 'r')
        stat_group = Marshal.load file.read
        file.close
        @logger.info("Read successfully, stats: #{stat_group}")
        result[group] = stat_group
      else
        result[group] = Hash.new(0)
      end
    }
    @stats = result
  end

  def write
    @file_map.each  { |group, file_name|
      @logger.info("Writing stats for group #{group}: #{file_name}")
      marshal_dump = Marshal.dump(@stats[group])
      file = File.new(file_name,'w')
      file.write marshal_dump
      file.close
    }
  end

  def to_s
    result = @stats.map { |group, stats|
      "#{group.to_s.gsub('_', ' ')}: #{stats.sort_by(&:last).reverse.to_h}"
    }.join(", ")
    result
  end

  def inc(group, stat)
    @stats[group][stat] = @stats[group][stat] + 1
  end
end

class Reddit
  def initialize
    @memes = {}
    @meme_hashes = {}
  end
  def get_meme(subreddit)
    if !@memes[subreddit] or @memes[subreddit].empty?
      # Time to get some fresh memes
      url = "https://www.reddit.com/#{subreddit}/top.json"
      response = Faraday.get url
      if response.status != 200
        loger.warn(response)
        raise "got status code #{response.status} from #{url}"
      end
      memes_raw = JSON.parse(response.body)
      memes = memes_raw['data']['children'].map { |e| e['data']['url'] }.select { |e| e.end_with?('jpg', 'png', 'gif') }
      # Let's keep a hash of the latest memes, so we don't repeat ourselves
      meme_hash = Digest::SHA1.hexdigest memes.sort.to_s
      if @meme_hashes[subreddit] && @meme_hashes[subreddit] == meme_hash
        # No new memes, so nothing to do.
      else
        @memes[subreddit] = memes
        @meme_hashes[subreddit] = meme_hash
      end
    end

    # Might not be that efficient, but we want memes _now_
    meme = @memes[subreddit].shuffle!.pop
  end
end

reddit = Reddit.new
# Nice source of "empty" memes.
# TODO: pick ones with a reasonable resolution.
no_meme_memes = [
  'http://tv90s.com/wp-content/uploads/2018/03/soundgarden-black-hole-sun-official-music-video.jpg',
  'https://www.dailydot.com/wp-content/uploads/2018/09/farquaad_markiplier_e_meme-409x400.jpg',
  'https://i.redd.it/b6i7pfzhgy0z.jpg',
  'https://www.meme-arsenal.com/memes/7a439222553a528730a5a1fd5f046c1f.jpg',
  'https://memegenerator.net/img/images/71690444.jpg'
]

default_sources = [
  'r/hmmm',
  'r/funny',
  'r/me_irl',
  'r/trebuchetmemes',
  'r/dankmemes',
  'r/wholesomememes',
  'r/itsaunixsystem',
  'r/softwaregore'
]

logger = Logger.new(STDOUT)
stats = Stats.new({ :requests_per_topic => 'requests_per_source_v1', :top_requesters => 'top_requesters_v1' }, logger)

begin
  logger.info('Starting...')
  Telegram::Bot::Client.run(token) do |bot|
    bot.listen do |message|
      case message.text
      when '/start'
        bot.api.send_message(chat_id: message.chat.id, text: "Hola #{message.from.first_name}")
      when '/stop'
        bot.api.send_message(chat_id: message.chat.id, text: "Buenas noches a todos")
      when '/stats'
        bot.api.send_message(chat_id: message.chat.id, text: "#{stats}")
      end
      # TODO: Read commands properly from MessageEntities
      if message.text and message.text.start_with?('/meme')
        source = message.text.split(' ')[1] || default_sources.sample
        if message.from
          stats.inc(:top_requesters, "#{message.from.first_name} #{message.from.last_name || ''}")
        end
        begin
          stats.inc(:requests_per_topic, source)
          meme = reddit.get_meme(source)
          if !meme
            logger.info('Meme not found, defaulting')
            meme = no_meme_memes.sample
            source = "Se acabaron los memes de #{source}, #{message.from.first_name}. Intenta otro reddit."
          end
        rescue => e
          logger.warn("Something went wrong, BSODing, #{e}")
          meme = 'http://media02.hongkiat.com/thumbs/640x410/blue-screen-of-death.jpg'
          source = "cuek. intenta otro reddit #{message.from.first_name}"
        end
        logger.info("Sending meme #{meme}, caption #{source}")
        bot.api.send_photo(chat_id: message.chat.id, photo: meme, caption: source)
        stats.write
      end
    end
  end
rescue StandardError => e
  logger.error(e)
ensure
  stats.write
end
