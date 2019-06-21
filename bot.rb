require 'telegram/bot'
require 'pp'
require 'nokogiri'
require 'open-uri'
require 'json'
require 'faraday'
require 'pry'
require 'rb-readline'
require 'digest'

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

def read_stats(file_name)
  if (File.exist?(file_name))
    puts "Reading stats: #{file_name}"
    file = File.open(file_name, 'r')
    result = Marshal.load file.read
    file.close
    puts "Read successfully, stats: #{result}"
    result
  end
end

def write_stats(stats, file_name)
  puts "Writing stats: #{file_name}"
  marshal_dump = Marshal.dump(stats)
  file = File.new(file_name,'w')
  file.write marshal_dump
  file.close
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

requests_per_source_file = 'requests_per_source_v1'

# Read stats
requests_per_source = read_stats(requests_per_source_file) || Hash.new(0)

begin
  puts 'Starting...'
  Telegram::Bot::Client.run(token) do |bot|
    bot.listen do |message|
      case message.text
      when '/start'
        bot.api.send_message(chat_id: message.chat.id, text: "Hola #{message.from.first_name}")
      when '/stop'
        bot.api.send_message(chat_id: message.chat.id, text: "Buenas noches a todos")
      when '/stats'
        bot.api.send_message(chat_id: message.chat.id, text: "Stats: #{requests_per_source.sort_by(&:last).reverse.to_h}")
      end
      # TODO: Read commands properly from MessageEntities
      if message.text and message.text.start_with?('/meme')
        source = message.text.split(' ')[1] || default_sources.sample
        begin
          requests_per_source[source] = requests_per_source[source] + 1
          meme = reddit.get_meme(source)
          if !meme
            puts 'Meme not found, defaulting'
            meme = no_meme_memes.sample
            source = "Se acabaron los memes de #{source}, #{message.from.first_name}. Intenta otro reddit."
          end
        rescue => e
          puts "Something went wrong, BSODing, #{e}"
          meme = 'http://media02.hongkiat.com/thumbs/640x410/blue-screen-of-death.jpg'
          source = "cuek. intenta otro reddit #{message.from.first_name}"
        end
        puts "Sending meme #{meme}, caption #{source}"
        bot.api.send_photo(chat_id: message.chat.id, photo: meme, caption: source)
      end
    end
  end
ensure
  write_stats requests_per_source, requests_per_source_file
end
