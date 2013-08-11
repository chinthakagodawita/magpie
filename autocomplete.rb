require 'mongo'
require 'rottentomatoes'
require 'logging'
require_relative 'api_keys'

# Never removed.
CACHE_PERMANENT = 0
# Removed on next cleanup.
CACHE_EXPIRED = -1

# Init the logger.
$logger = Logging.logger('vcdq-autocomplete.log')
$logger.add_appenders(
  Logging.appenders.stdout
)
$logger.level = :debug

# Init MongoDB.
include Mongo
db = MongoClient.new('localhost', 27017).db('vcdq')
$autocomplete_collection = db.collection('autocomplete')

# Init RT API.
include RottenTomatoes
Rotten.api_key = RT_API_KEY

def get_suggestions (string)
  # Check and return if we have this search in our cache.
  cached_data = cache_get(string)
  return cached_data if !cached_data.nil?

  $logger.debug('NOT returning from cache')

  $logger.debug(cached_data)

  # Nothing in the cache, let's query RT.
  results = RottenMovie.find(:title => string)
  parsed_results = Array.new

  results.each do |result|
    # We only care about a few properties.
    parsed_result = {
      title: result.title,
      year: result.year,
      ratings: {
        critics: result.ratings.critics_score,
        audience: result.ratings.audience_score
      },
      img: result.posters.original,
      api_ids: {
        rt: result.id,
        imdb: nil
      }
    }

    # Add IMDB ID if the result has it.
    if !result.alternate_ids.nil? && !result.alternate_ids.imdb.nil?
      parsed_result[:api_ids][:imdb] = result.alternate_ids.imdb
    end

    parsed_results.push(parsed_result)
  end

  # Cache search in mongo so that we don't keep querying RT all the time.
  # Expiry set to 2 weeks.
  expiry = Time.now + (60 * 60 * 24 * 7 * 2)
  cache_set(string, parsed_results, expiry)

  return parsed_results
end

def cache_set (cid, data, expiry = CACHE_PERMANENT)
  $autocomplete_collection.update({
    _id: cid
  }, {
    _id: cid,
    cid: cid,
    data: data,
    expiry: expiry
  }, {upsert: true})
end

def cache_get (cid)
  return $autocomplete_collection.find_one({
    _id: cid
  })
end

def cache_flush (flush_all = false)
  if !flush_all
    # Only remove expired data.
    expired_cache_data = $autocomplete_collection.remove({
      expiry: {
        '$lte' => Time.now,
        '$ne' => 0
      }
    })
  else
    # Remove everything (careful: this removes 'permanent' cache items too!).
    expired_cache_data = $autocomplete_collection.remove()
  end
end

def get_session_id ()
  return (0...50).map{ ('a'..'z').to_a[rand(26)] }.join
end

suggestions = get_suggestions('hang')
$logger.debug(suggestions)
cache_flush(true)
