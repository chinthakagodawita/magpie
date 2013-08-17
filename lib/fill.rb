require 'feedzirra'
require 'mongo'
require 'logging'

# Build custom URL: 'Scene+P2P', 'DVDRip' (or greater), only new (last 3 years).
VCDQ_RSS_URL_BASE = 'http://www.vcdq.com/browse/rss/1/1_2/3_2/9_11_3_2/0'
current_year = Time.now.year
vcdq_rss_url = "#{VCDQ_RSS_URL_BASE}/#{current_year-2}_#{current_year-1}_#{current_year}/0"

# Save indicators
SAVED_UNCHANGED = 1
SAVED_NEW = 2

# Init the logger.
$logger = Logging.logger('vcdq-fill.log')
$logger.add_appenders(
  Logging.appenders.stdout
)
$logger.level = :debug

# Init MongoDB.
include Mongo
db = MongoClient.new('localhost', 27017).db('vcdq')
movies_collection = db.collection('movies')

# Get movie info for the title
# @see http://en.wikipedia.org/wiki/Standard_(warez)#Naming
def get_movie_info (title_parts, categories)
  title = ''
  # We could have multiple years, save all that we find
  years_found = Hash.new
  # We know that the quality is always the fourth category.
  quality = categories[3]

  # Iterate over all the title parts looking for years (there could be many!)
  title_parts.each_with_index do |title_part, title_index|
    if title_part =~ /^[0-9]{4}$/
      years_found[title_index] = title_part
    end
  end

  # If we have a year, brilliant, let's use it!
  if years_found.length > 0
    # Only the final year will be the year of the movie
    year = years_found.values[-1]
    title_boundary = years_found.keys[-1]
  else
    # If no year, we have a problem, let's try find a word with capitals
    # and assume that as the title boundary (e.g. 'UNRATED')
    title_boundary = nil
    year = -1

    title_parts.each_with_index do |title_part, title_index|
      if title_part =~ /^[A-Z]{2}/
        title_boundary = title_index
        break
      end
    end
  end

  # If there's nothing at this point, make a wild guess and try using the
  # quality as the boundary.
  if title_boundary.nil?
    # See if the quality is in the title.
    title_parts.each_with_index do |title_part, title_index|
      if title_part == quality
        title_boundary = title_index
        break
      end
    end
  end

  # If we still have nothing, sorry, there's nothing I can do
  # @TODO: Throw exception instead
  if title_boundary.nil?
    $logger.debug "Could not parse movie info for title '#{title_parts.join('.')}'"
    return nil
  end

  actual_title_parts = title_parts.slice(0, title_boundary)
  title = actual_title_parts.join(' ')

  return {
    title: title,
    year: year,
    quality: quality
  }
end

# Save a movie into mongo.
# @TODO: Error checking.
def save_movie (movie, collection)
  # Only insert this movie if it doesn't already exist (not quite an 'upsert').
  movie_exists = collection.find_one({
    _id: movie[:_id]
  });
  if !movie_exists
    # Do an insert of this movie.
    collection.insert(movie)
    return SAVED_NEW
  end

  return SAVED_UNCHANGED
end

# Save a release as part of a movie in mongo.
# @TODO: Error checking.
# @TODO: Check if inserted or not and return appropriate flag
def save_release (release, movie_id, collection)
  # Do an insert of this release if it's not already there.
  collection.update({
    _id: movie_id,
    'releases.url' => {
      '$ne' => release[:url]
    }
  }, {
    '$push' => {
      releases: release
    }
  })

  return SAVED_NEW
end

def get_movie_document_id (title, year)
  return title.gsub(' ', '').downcase + ':' + year.to_s
end

# response = RSS::Parser.parse(VCDQ_RSS_URL, false)
# feed_parsed = response.channel.items

def get_latest_movies (vcdq_rss_url, movies_collection)
  # @TODO: Error checking.
  feed = Feedzirra::Feed.fetch_raw(vcdq_rss_url)
  feed_parsed = Feedzirra::Feed.parse(feed)

  current_date = Time.now

  i = 0
  feed_parsed.entries.each do |movie_item|
    movie_title_parts = movie_item.title.split('.')

    # puts movie_item
    $logger.debug("Processing title: #{movie_item.title}")

    # Parse the title and categories for useful info.
    movie_info = get_movie_info(movie_title_parts, movie_item.categories)

    # If we couldn't parse any info, just log this incident and move on
    # @TODO: reformat to throw exception instead
    next if movie_info.nil?

    # Create a movie.
    movie_document_id = get_movie_document_id(movie_info[:title], movie_info[:year])
    movie = {
      _id: movie_document_id,
      title: movie_info[:title],
      title_lower: movie_info[:title].downcase,
      year: movie_info[:year],
      created: current_date,
      releases: Array.new
    }
    save_movie(movie, movies_collection)

    # Create a release
    release = {
      quality: movie_info[:quality],
      url: movie_item.url,
      date: movie_item.published,
      created: current_date
    }
    save_release(release, movie_document_id, movies_collection)

    # $logger.debug("Parsed movie info: #{movie_info}")

    i += 1
  end

  $logger.debug("======== only #{i}/#{feed_parsed.entries.length} were good")
end

get_latest_movies(vcdq_rss_url, movies_collection)
