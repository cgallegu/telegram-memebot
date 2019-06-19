require 'telegram/bot'
require 'pp'
require 'nokogiri'
require 'open-uri'
require 'json'

token = ''

def get_memes
  doc = Nokogiri::HTML(open('https://9gag.com/trending'))
  raw_memes = doc.css('script[type="application/ld+json"]')[0]
  memes = JSON.parse(raw_memes.text)['itemListElement'].map { |e| e['url'] }
  meme_id_regex = /https:\/\/9gag.com\/gag\/(.*)\/.*/
  meme_ids = memes.map { |e| e.match(meme_id_regex)[1]  }
  meme_image_urls = meme_ids.map { |e| "https://img-9gag-fun.9cache.com/photo/#{e}_460s.jpg"  }
  meme_image_urls
end


Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    pp message
    pp message.entities
    case message.text
    when '/start'
      bot.api.send_message(chat_id: message.chat.id, text: "Hola #{message.from.first_name}")
    when '/stop'
      bot.api.send_message(chat_id: message.chat.id, text: "Buenas noches a todos")
    when '/meme'
      bot.api.send_photo(chat_id: message.chat.id, photo: get_memes.sample)
    end
  end
end
