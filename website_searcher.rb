require 'csv'
require 'thread'

THREAD_COUNT = 20

FILE_INPUT = 'urls.txt'.freeze
FILE_OUTPUT = 'results.txt'.freeze

def main
  fail 'Please enter search term as a first param' if ARGV.empty?

  term = ARGV[0]
  sites = Reader.read

  searcher = Searcher.new(sites, term)
  result = searcher.perform
  Data.save(result) if result.any?
  p searcher.errors if searcher.errors.any?
end

class Data
  def self.read
    CSV.read(FILE_INPUT, headers: :first_row).map { |i| i['URL'] }
  end

  def write(sites)
    File.open(FILE_OUTPUT, 'w') do |f|
      sites.each { |site| f.write(site) }
    end
  rescue => e
    p 'Unable to save file'
    p e
  end
end

class Searcher
  attr_reader :errors

  def initialize(sites, term)
    @sites = sites
    @term = term

    @result = []
    @errors = []

    @queue = Queue.new
    @mutes ||= Mutex.new
  end

  def perform
    @sites.each { |site| @queue << site }
    threads = []
    [THREAD_COUNT, @queue.length].min.times do
      threads << Thread.new do
        start_search
      end
    end

    threads.map(&:join)
    @results
  end

  private

  def start_search
    while site = @queue.pop(true)
      Site.new(site)
      if Site.check(@term)
        @mutes.syncronize { @result << site }
      else
        @errors << Site.error if Site.has_error
      end
    end
  end
end

class Site
  attr_reader :url, :error
  def initialize(url)
    @url = url
    @error = nil
  end

  def check(term)
    body = get_body
    valid = false
    valid = check_body(body, term) unless body.nil?
    valid
  end

  def get_body
    uri = URI(@url)
    response = Net::HTTP.get_response(uri)
    case response
    when Net::HTTPSuccess, Net::HTTPRedirection
      response.body
    end
  rescue => e
    @error = e
  end

  def check_response(body, term)
    Regexp.new(term, true) =~ body
  end
end

main if __FILE__ == $PROGRAM_NAME
