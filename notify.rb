require 'mongo'
require 'logging'
require 'net/https'
require 'json'
require 'api_keys'

PUSHOVER_API_URL = 'https://api.pushover.net/1/messages.json'

NOTIFY_SUCCESS = 1
NOTIFY_SERVER_ERROR = 2
NOTIFY_REQUEST_ERROR = 3

# Init the logger.
$logger = Logging.logger('vcdq-notify.log')
$logger.add_appenders(
  Logging.appenders.stdout
)
$logger.level = :debug

# Init MongoDB.
include Mongo
db = MongoClient.new('localhost', 27017).db('vcdq')
notifications_collection = db.collection('notify')
users_collection = db.collection('users')
movies_collection = db.collection('movies')

def save_sample_notifications (collection)
  notification_1 = {
    sent: false,
    title: "Epic",
    title_lower: "epic",
    year: -1,
    user: 1
  }
  collection.update(notification_1, notification_1, {upsert: true})
  notification_2 = {
    sent: false,
    title: "Brave",
    title_lower: "brave",
    year: -1,
    user: 1
  }
  collection.update(notification_2, notification_2, {upsert: true})
  notification_3 = {
    sent: false,
    title: "Olympus Has Fallen",
    title_lower: "olympus has fallen",
    year: -1,
    user: 1
  }
  collection.update(notification_3, notification_3, {upsert: true})
  notification_4 = {
    sent: false,
    title: "Assault on Wall Street",
    title_lower: "assault on wall street",
    year: -1,
    user: 1
  }
  collection.update(notification_4, notification_4, {upsert: true})
end

def save_sample_users (collection)
  user1 = {
    _id: 1,
    username: 'chin',
    email: 'chin.godawita@me.com',
    apis: {
      pushover: {
        key: PUSHOVER_API_KEY_CHIN
      }
    }
  }
  collection.update(user1, user1, {upsert: true})
end

def build_notification_message (movie)
  # Build a list of releases.
  releases = Array.new
  movie['releases'].each do |release|
    $logger.debug(release['quality'])
    releases.push(release['quality'])
  end
  return "Movie on watch list released: #{movie['title']}, Release(s): #{releases.join(', ')}"
end

def send_pushover_notification (message, user)
  # Pushover only support 512 chars, truncate if we hit the limit.
  if (message.length > 512)
    # Reserve 3 characters for ellipsis, need to indicate the truncation
    # somehow.
    message = message.slice(0, 409) + '...'
  end

  url = URI.parse(PUSHOVER_API_URL)
  params = {
    'token' => PUSHOVER_API_KEY,
    'user' => user['apis']['pushover']['key'],
    'message' => message,
  }

  # Open HTTPS connection.
  https = Net::HTTP.new(url.host, url.port)
  https.use_ssl = true
  https.verify_mode = OpenSSL::SSL::VERIFY_PEER

  # Create request.
  request = Net::HTTP::Post.new(url.path)
  request.set_form_data(params)

  # Send request and ask for response.
  response = https.request(request)

  # The response is sent as JSON.
  response_code = response.code.to_i
  response_body = JSON.parse(response.body)

  # Set proper error code according to Pushover response.
  # @see https://pushover.net/api#friendly.
  notify_response = NOTIFY_SUCCESS if (response_code == 200 && response_body['status'] == 1)
  notify_response = NOTIFY_SERVER_ERROR if notify_response.nil? && ((response_code < 500 && response_code > 399) || response_body['status'] != 1)
  notify_response = NOTIFY_REQUEST_ERROR if notify_response.nil?

  return notify_response
end

def find_matching_movie (title_lower, year, collection)
  search_params = {
    title_lower: title_lower
  }

  # Search using year too if we have a valid one.
  if (year > -1) {
    search_params[:year] = year
  }

  return collection.find_one(search_params)
end

def load_unsent_notifications (collection)
  return collection.find({
    sent: false
  })
end

# save_sample_notifications(notifications_collection)
# save_sample_users(users_collection)
# exit

notifications = load_unsent_notifications(notifications_collection)
# Cache user loads.
users = Hash.new

notifications.each do |notification|
  user_id = notification['user']
  # Get the user that wants this notification (use cached if we have it).
  user = users.has_key?(user_id) ? users[user_id] : users_collection.find_one({_id: user_id})
  users[user_id] = user

  # See if we have a matching movie.
  movie = find_matching_movie(notification['title_lower'], notification['year'], movies_collection)

  # If we don't, continue to the next.
  next if movie.nil?

  # If we have a movie, notify the user.
  notification_message = build_notification_message(movie)
  notify_success = send_pushover_notification(notification_message, user)

  $logger.debug("Success was #{notify_success}")

  $logger.debug("title: #{notification['title_lower']}")
  $logger.debug("msg: #{notification_message}")
  $logger.debug(movie)
end
