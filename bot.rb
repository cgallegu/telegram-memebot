require 'telegram/bot'
require 'telegram/bot/types'
require 'json'
require 'logger'

class Reddit
  def initialize(logger)
    @memes = {}
    @meme_hashes = {}
    @logger = logger
    logger.info "Initializing HTTP connection"
    @conn = Faraday.new(:url => 'https://www.reddit.com')
    logger.info "Done"
    logger.info "Initialized Reddit Client"
  end

  def get_meme(subreddit)
    if !@memes[subreddit] or @memes[subreddit].empty?
      @logger.info "#{@memes[subreddit]}"
      # Time to get some fresh memes
      url = "#{subreddit}/top.json"
      @logger.info "Calling Reddit"
      response = @conn.get url
      @logger.info "Done"
      if response.status != 200
        # loger.warn(response)
        raise "got status code #{response.status} from #{url}"
      end
      @logger.info "Parsing json"
      memes_raw = JSON.parse(response.body)
      @logger.info "Done"
      @logger.info "Parsing memes"
      memes = memes_raw['data']['children'].map { |e| e['data']['url'] }.select { |e| e.end_with?('jpg', 'png', 'gif') }
      @logger.info "Got #{memes.length} memes"
      @memes[subreddit] = memes
      @meme_hashes[subreddit] = meme_hash
      #end
    end

    # Might not be that efficient, but we want memes _now_
    meme = @memes[subreddit].shuffle!.pop
    @logger.info "#{@memes[subreddit].length} memes left"
    meme
  end
end

$logger = Logger.new(STDOUT)
$reddit = Reddit.new($logger)

def lambda_handler(event:, context:)
  logger = $logger
  logger.level = ENV['LOGGER_LEVEL']
  token = ENV['TELEGRAM_MEMEBOT_TOKEN']
  logger.debug "Started"
  logger.debug "event: #{event}"
  body_json = event["body"]
  logger.debug "body (json): #{body_json}"
  body = JSON.parse(body_json)
  logger.debug "body (parsed): #{body}"
  update = Telegram::Bot::Types::Update.new(body)
  logger.debug "update: #{update}"
  message = update.current_message
  logger.debug "message (parsed): #{message}"

  reddit = $reddit
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

  logger.debug "Bot client initialized"
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
    begin
      logger.info("Getting meme from reddit")
      meme = reddit.get_meme(source)
      logger.info("Done")
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
  end
  telegram_body = {
    :method => 'sendPhoto',
    :chat_id  => message.chat.id,
    :photo => meme,
    :caption => source
  }.to_json

  logger.info("Telegram body: #{telegram_body}")

  {
    isBase64Encoded: false,
    statusCode: 200,
    body: telegram_body
  }
end
