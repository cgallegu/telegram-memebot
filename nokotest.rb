require 'nokogiri'
require 'open-uri'
require 'pp'
require 'rb-readline'
require 'pry'
require 'json'


doc = Nokogiri::HTML(open('https://9gag.com/trending'))
raw_memes = doc.css('script[type="application/ld+json"]')[0]
memes = JSON.parse(raw_memes.text)['itemListElement'].map { |e| e['url'] }
meme_id_regex = /https:\/\/9gag.com\/gag\/(.*)\/.*/
meme_ids = memes.map { |e| e.match(meme_id_regex)[1]  }
meme_image_urls = meme_ids.map { |e| "https://img-9gag-fun.9cache.com/photo/#{e}_460s.jpg"  }
puts meme_image_urls
# puts "https://img-9gag-fun.9cache.com/photo/#{meme_id}_460s.jpg"
