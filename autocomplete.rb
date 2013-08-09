# require 'mongo'
require 'imdb'
require 'logging'

# Init the logger.
$logger = Logging.logger('vcdq-autocomplete.log')
$logger.add_appenders(
  Logging.appenders.stdout
)
$logger.level = :debug

# Init MongoDB.
# include Mongo
# db = MongoClient.new('localhost', 27017).db('vcdq')
# notifications_collection = db.collection('notify')
# users_collection = db.collection('users')

def get_suggestions_from_imdb (string)
  # Cache IMDB in mongo.
  IMDB::Configuration.caching = true
  IMDB::Configuration.db(
    :hostname => "localhost",
    :database => "vcdq_imdb"
  )

  search = IMDB::Search.new

  search.movie(string).each do |result|
    # movie = IMDB::Movie.new(result.id)
    $logger.debug('possible movie:' + "\n")
    $logger.debug(result)
    # break if !result.nil?
  end
end

$logger.debug(get_suggestions_from_imdb('hang'))
