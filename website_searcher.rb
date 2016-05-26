require 'csv'
require 'thread'
require 'uri'
require 'net/http'
# require 'logger'

THREAD_COUNT = 20

FILE_INPUT = 'urls.txt'.freeze
FILE_OUTPUT = 'results.txt'.freeze

# $logger = Logger.new('| tee logfile.log')
# if !ENV['DEBUG'].nil? && ENV['DEBUG'] == 'true'
# $logger.level = Logger::DEBUG
# else
# $logger.level = Logger::WARN
# end

def main
  fail 'Please enter search term as a first param' if ARGV.empty?
  # $logger.info "Start"
  term = ARGV[0]
  sites = Data.read

  # $logger.info "term: #{term}"

  searcher = Searcher.new(sites, term)
  results = searcher.perform
  Data.write(results) if results.any?
  # $logger.warn "Errors with sites: #{searcher.errors}" if searcher.errors.any?
  # $logger.info "Finish"
end

class Data
  def self.read
    CSV.read(FILE_INPUT, headers: :first_row).map { |i| i['URL'] }
  end

  def self.write(sites)
    File.open(FILE_OUTPUT, 'w') do |f|
      sites.each { |site| f.puts(site) }
    end
  rescue => e
    # $logger.error "Unable to save file: #{e}"
  end
end

class Searcher
  attr_reader :errors

  def initialize(sites, term)
    @sites = sites
    @term = term

    @results = []
    @errors = []

    @queue = Queue.new
    @mutes ||= Mutex.new

    @length = @sites.length
    @count = 0
  end

  def perform
    @sites.each { |site| @queue << site }
    threads = []
    [THREAD_COUNT, @queue.length].min.times do
      threads << Thread.new { start_search }
    end
    threads.map(&:join)
    @results
  end

  private

  def start_search
    while !@queue.empty? && url = @queue.pop
      @mutes.synchronize { @count += 1 }
      print "\e[34m#{@count}\e[0m\n"

      site = Site.new(url)
      if site.check(@term)
        @mutes.synchronize { @results << site }
      else
        @errors << "site #{site} - #{site.error}" unless site.error.nil?
      end
    end
  end
end

class Site
  attr_reader :url, :error
  alias :to_s :url

  def initialize(url)
    @url = url
    @error = nil
    parse_default_url
  end

  def check(term)
    valid = false
    body = get_body(@uri)
    valid = check_body(body, term) unless body.nil?
    # $logger.debug "check: #{valid} - #{@url} "
    valid
  end

  def get_body(uri, limit = 10)
    fail ArgumentError, 'HTTP redirect too deep' if limit == 0
    # $logger.debug uri.to_s
    body = nil
    begin
      response = Net::HTTP.get_response(uri)

      case response
      when Net::HTTPSuccess
        # $logger.debug "Site #{@url}, body length: #{response.body.length}"
        body = response.body
      when Net::HTTPRedirection
        # $logger.debug "Redirect: #{11 - limit}"
        uri = get_redirect_uri(response['location'])
        body = get_body(uri, limit - 1)
      end
    rescue SocketError, Net::OpenTimeout  => e
      #first check - try to add www
      if limit == 10
        uri.hostname = "www.#{uri.hostname}"
        body = get_body(URI(uri.to_s), limit - 1)
      else
        @error = e
      end
    rescue => e
      @error = e
    end
    body
  end

  def check_body(body, term)
    !(Regexp.new(term, true) =~ body).nil?
  end

  def get_redirect_uri(url)
    uri = URI(url)
    # save redirected host/scheme
    if uri.hostname.nil?
      uri.hostname = @uri.hostname
    else
      @uri.hostname = uri.hostname
    end

    if uri.scheme.nil?
      uri.scheme = @uri.scheme
    else
      @uri.scheme = uri.scheme
    end

    #fix redirect path
    if !uri.path.nil? && uri.path[0] != '/'
      uri.path = "/#{uri.path}"
    end

    URI(uri.to_s)
  end

  def parse_default_url
    @uri = URI(@url)
    @uri.scheme = 'http' if @uri.scheme.nil?
    if @uri.hostname.nil?
      path = @uri.path.split('/')
      @uri.hostname = path.pop
      @uri.path = path.empty? ? '/' : path.join('/')
    end
    @uri = URI(@uri.to_s)
  end
end

main if __FILE__ == $PROGRAM_NAME
