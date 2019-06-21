require 'telegram/bot'
require 'pp'
require 'nokogiri'
require 'open-uri'
require 'json'
require 'faraday'
require 'pry'
require 'rb-readline'

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

class Reddit
  def initialize
    @memes = {}
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
      @memes[subreddit] = memes_raw['data']['children'].map { |e| e['data']['url'] }.select { |e| e.end_with?('jpg', 'png', 'gif') }
    end

    # Might not be that efficient, but we want memes _now_
    meme = @memes[subreddit].shuffle!.pop
  end
end

reddit = Reddit.new

Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    case message.text
    when '/start'
      bot.api.send_message(chat_id: message.chat.id, text: "Hola #{message.from.first_name}")
    when '/stop'
      bot.api.send_message(chat_id: message.chat.id, text: "Buenas noches a todos")
    end
    # TODO: Read commands properly from MessageEntities
    if message.text and message.text.start_with?('/meme')
      source = message.text.split(' ')[1] || 'r/hmmm'
      begin
        meme = reddit.get_meme(source)
        if !meme
          puts 'Meme not found, defaulting'
          meme = 'http://tv90s.com/wp-content/uploads/2018/03/soundgarden-black-hole-sun-official-music-video.jpg'
          source = "Niun meme ahi, #{message.from.first_name}"
        end
      rescue
        puts 'Something went wrong, BSODing'
        meme = 'http://media02.hongkiat.com/thumbs/640x410/blue-screen-of-death.jpg'
        source = "cuek. intenta otro reddit #{message.from.first_name}"
      end
      puts "Sending meme #{meme}, caption #{source}"
      bot.api.send_photo(chat_id: message.chat.id, photo: meme, caption: source)
    end
  end
end
