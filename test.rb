require 'rss'
require 'feedzirra'

# @TODO: See if we can get a saner URL
VCDQ_RSS_URL = 'http://www.vcdq.com/browse/rss/1/1_2/3_2/9_11_3_2/0/2011_2012_2013_2014/0'

# Get movie info for the title
# @see http://en.wikipedia.org/wiki/Standard_(warez)#Naming
def get_movie_info (title_parts)
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

    # If we still have nothing, sorry, there's nothing I can do
    # @TODO: Log this incident and continue to the next title
    return nil if title_boundary.nil?
  end

  # Now check for the quality
  # The last title part will always be the group name (and sometimes the codec)
  # We don't need it, let's discard it
  title_parts.pop

  # @TODO: Load this
  # @TODO: add a 'matching type', e.g. some values will check for equality,
  # others for partials
  possible_sources = [
    'BluRay',
    'BDRip',
    'HDRip',
    'DVD',
    'DVDRip',
    'DVD-Rip',
    'BRRip',
    'BR-Rip',
    'Web' # @TODO: add partial match support,
  ]

  # Also iterate over possible sources, removing the '-' (if in the middle of a
  # word) and adding the resulting value to the array

  # Downcase possible source to minimise error
  possible_sources.map!{|c| c.downcase}

  # Going backwards through the remaining parts, see if they match one of
  # our source keywords.
  # If they do, brilliant, we now have a source
  source = nil
  source_index = nil
  title_parts_reverse = title_parts.reverse
  title_parts_reverse.each_with_index do |title_part, title_index|
    if possible_sources.include? title_part.downcase
      source = title_part
      source_index = title_index
      break
    end
  end

  # This is really only relevant if we're dealing with a HD source
  quality = nil

  actual_title_parts = title_parts.slice(0, title_boundary)
  title = actual_title_parts.join(' ')

  return {
    title: title,
    year: year,
    source: source,
    quality: quality
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
feed = Feedzirra::Feed.fetch_raw(VCDQ_RSS_URL)
# puts feed
# feed.sanitize_entries!
feed_parsed = Feedzirra::Feed.parse(feed)
feed_parsed = feed_parsed.entries
# puts feed_parsed.items
# puts feed.url
# puts feed.feed_url
puts "======== loaded #{feed_parsed.length} items"
i = 0
feed_parsed.each do |movie|
  movie_title_parts = movie.title.split('.')

  # Only continue if this movie meets our strict criteria
  # @TODO: Save this record for later so that we ignore it in future
  next if !does_movie_meet_criteria(movie_title_parts)

  puts '=== found a movie: ==='
  # puts movie
  puts movie.title

  puts movie.categories

  # puts movie_title_parts
  movie_info = get_movie_info(movie_title_parts)

  # If we couldn't parse any info, just log this incident and move on
  # @TODO: reformat to throw exception instead
  next if movie_info.nil?

  puts "\tTITLE: #{movie_info[:title]}"
  puts "\tYEAR: #{movie_info[:year]}"

  puts movie_info

  i = i+1
end

puts "======== only #{i} were good"

# puts feed
