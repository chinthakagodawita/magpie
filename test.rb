require 'rss'
require 'feedzirra'

# Build custom URL: 'Scene+P2P', 'DVDRip' (or greater), only new (last 3 years).
VCDQ_RSS_URL_BASE = 'http://www.vcdq.com/browse/rss/1/1_2/3_2/9_11_3_2/0'
current_year = Time.now.year
vcdq_rss_url = "#{VCDQ_RSS_URL_BASE}/#{current_year-2}_#{current_year-1}_#{current_year}/0"

# Get movie info for the title
# @see http://en.wikipedia.org/wiki/Standard_(warez)#Naming
def get_movie_info (title_parts, categories)
  title = ''
  # We could have multiple years, save all that we find
  years_found = Hash.new

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
    # We know that the quality is always the fourth category.
    quality = categories[3]
    title_parts.each_with_index do |title_part, title_index|
      if title_part == quality
        title_boundary = title_index
        break
      end
    end
  end

  # If we still have nothing, sorry, there's nothing I can do
  # @TODO: Log this incident and continue to the next title
  return nil if title_boundary.nil?

  actual_title_parts = title_parts.slice(0, title_boundary)
  title = actual_title_parts.join(' ')

  return {
    title: title,
    year: year
  }
end

# Checks to see if movie meets a certain set of critera
# @TODO: Load criteria instead of hardcoding
def does_movie_meet_criteria (title_parts)
  bad_criteria = ['CAM', 'TS']

  title_parts.each do |title_part|
    return false if bad_criteria.include? title_part
  end

  return true
end

# response = RSS::Parser.parse(VCDQ_RSS_URL, false)
# feed_parsed = response.channel.items
feed = Feedzirra::Feed.fetch_raw(vcdq_rss_url)
feed_parsed = Feedzirra::Feed.parse(feed)

puts "======== loaded #{feed_parsed.entries.length} items"
i = 0
feed_parsed.entries.each do |movie|
  movie_title_parts = movie.title.split('.')

  # Only continue if this movie meets our strict criteria
  # @TODO: Save this record for later so that we ignore it in future
  next if !does_movie_meet_criteria(movie_title_parts)

  puts '=== found a movie: ==='
  # puts movie
  puts movie.title

  movie_info = get_movie_info(movie_title_parts, movie.categories)

  # If we couldn't parse any info, just log this incident and move on
  # @TODO: reformat to throw exception instead
  next if movie_info.nil?

  # We know that the fourth category is always the quality, save it for later.
  movie_info[:quality] = movie.categories[3]

  puts movie_info

  i += 1
end

puts "======== only #{i} were good"

# puts feed
