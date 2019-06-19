require 'faraday'
require 'digest'
require 'pp'
require 'securerandom'

class Gag
  API = 'http://api.9gag.com'

  def initialize()
    @app_id = 'com.ninegag.android.app'
    @token = random_sha1()
    @device_uuid = random_uuid()
    pp self
  end

  def trending
    path = '/v2/post-list'
    headers = {
      '9GAG-9GAG_TOKEN' => @token,
      '9GAG-TIMESTAMP' => get_timestamp().to_s,
      '9GAG-APP_ID' => @app_id,
      'X-Package-ID' => @app_id,
      '9GAG-DEVICE_UUID' => @device_uuid,
      'X-Device-UUID' => @device_uuid,
      '9GAG-DEVICE_TYPE' => 'android',
      '9GAG-BUCKET_NAME' => 'MAIN_RELEASE',
    }

    headers['9GAG-REQUEST-SIGNATURE'] = sign_request(
       headers['9GAG-TIMESTAMP'],
       headers['9GAG-APP_ID'],
       headers['9GAG-DEVICE_UUID']
    )

    pp headers
    Faraday.new(API + path, headers: headers).get
  end

  private
  def random_sha1
    sha = Digest::SHA1.new
    sha.update(Time.now.getutc.to_s)
    sha.hexdigest()
  end

  def random_uuid
    SecureRandom.uuid
  end

  def get_timestamp
    Time.now.to_i * 1000
  end

  def sign_request(timestamp, app_id, device_uuid)
    sha = Digest::SHA1.new
    sha.update("*#{timestamp}_._#{app_id}._.#{device_uuid}9GAG")
    sha.hexdigest()
  end


end

c = Gag.new
pp c.trending
