require 'pry'
require 'rest-client'
require 'json'
require 'optparse'

BACKEND_AG = 'ag'
BACKEND_4STORE = '4store'
GOO_HOST = 'localhost'
AG_USERNAME = 'test'
AG_PASSWORD = 'xyzzy'
DEF_AG_PORT = 10035
DEF_4STORE_PORT = 9000
JOB_NAME = 'bioportal'
DEF_VERSION = 'latest'
REDIS_PORT = 6379
@options = nil

def main
  @options = parse_options
  pull_cmd = ''

  if @options[:backend] == BACKEND_AG
    @options[:backend_port] = DEF_AG_PORT if @options[:backend_port] <= 0
    puts "\nUsing AllegroGraph #{@options[:version]} on port #{@options[:backend_port]}...\n\n"
    pull_cmd = "docker pull franzinc/agraph:#{@options[:version]}"
  elsif @options[:backend] == BACKEND_4STORE
    @options[:backend_port] = DEF_4STORE_PORT if @options[:backend_port] <= 0
    puts "\nUsing 4store #{@options[:version]} on port #{@options[:backend_port]}...\n\n"
    pull_cmd = "docker pull bde2020/4store:#{@options[:version]}"
  end
  pulled = system("#{pull_cmd}")
  abort("Unable to pull the #{@options[:backend]} Docker image: #{@options[:version]}. Aborting...\n") unless pulled
  resp = true

  begin
    if @options[:backend] == BACKEND_AG
      container_name = "#{@options[:backend]}-#{@options[:version]}-#{@options[:backend_port]}"
      run_cmd = "docker run -d --rm -e AGRAPH_SUPER_USER=#{AG_USERNAME} -e AGRAPH_SUPER_PASSWORD=#{AG_PASSWORD} -p #{@options[:backend_port]}:#{DEF_AG_PORT} --shm-size 1g --name #{container_name} franzinc/agraph:#{@options[:version]}"
      puts "\n#{run_cmd}\n\n"
      system("#{run_cmd}")
      sleep(5)

      # If you need to upload a patch to the AG container, uncomment this code
      # tmp_cmd = "docker cp /Users/mdorf/Downloads/patch-spr45071-bug26235.cl #{container_name}:agraph/lib/patches/patch-spr45071-bug26235.cl"
      # system("#{tmp_cmd}")
      # tmp_cmd = "docker exec -u root -t -i #{container_name} /agraph/bin/agraph-control --config /agraph/etc/agraph.cfg stop"
      # system("#{tmp_cmd}")
      # sleep(5)
      # tmp_cmd = "docker exec -u root -t -i #{container_name} /agraph/bin/agraph-control --config /agraph/etc/agraph.cfg start"
      # system("#{tmp_cmd}")
      # sleep(5)

      ag_rest_call("/repositories/#{JOB_NAME}", 'PUT')
      ag_rest_call('/users/anonymous', 'PUT')
      ag_rest_call("/users/anonymous/access?read=true&write=true&repositories=#{JOB_NAME}", 'PUT')
    elsif @options[:backend] == BACKEND_4STORE
      run_cmd = "docker run -d --rm -p #{@options[:backend_port]}:#{@options[:backend_port]} --name #{@options[:backend]}-#{@options[:version]}-#{@options[:backend_port]} bde2020/4store:#{@options[:version]}"
      exec_cmd1 = "docker exec #{@options[:backend]}-#{@options[:version]}-#{@options[:backend_port]} 4s-backend-setup --segments 4 #{JOB_NAME}"
      exec_cmd2 = "docker exec #{@options[:backend]}-#{@options[:version]}-#{@options[:backend_port]} 4s-admin start-stores #{JOB_NAME}"
      exec_cmd3 = "docker exec #{@options[:backend]}-#{@options[:version]}-#{@options[:backend_port]} 4s-httpd -s-1 -p#{@options[:backend_port]} #{JOB_NAME}"
      puts "\n#{run_cmd}\n\n"
      system("#{run_cmd}")
      system("#{exec_cmd1}")
      system("#{exec_cmd2}")
      sleep(5)
      system("#{exec_cmd3}")
      sleep(1)
    end

    # start redis container
    puts "starting redis container on port #{@options[:redis_port]}"
    run_cmd4 = "docker run -p #{@options[:redis_port]}:6379  --name redis-#{@options[:redis_port]} -d redis"
    system("#{run_cmd4}")

    test_cmd = 'bundle exec rake test'
    test_cmd << " TEST=\"#{@options[:filename]}\"" unless @options[:filename].empty?
    test_cmd << ' TESTOPTS="-v"'
    test_cmd.gsub!(/"$/, " --name=#{@options[:test]}\"") unless @options[:test].empty?
    puts "\n#{test_cmd}\n\n"

    ENV['OVERRIDE_CONNECT_GOO'] = 'true'
    ENV['GOO_HOST'] = GOO_HOST
    ENV['GOO_PORT'] = @options[:backend_port].to_s
    ENV['GOO_BACKEND_NAME'] = @options[:backend]
    ENV['GOO_REDIS_PORT'] = @options[:redis_port].to_s
    ENV['HTTP_REDIS_PORT'] = @options[:redis_port].to_s

    if @options[:backend] == BACKEND_AG
      ENV['GOO_PATH_QUERY'] = "/repositories/#{JOB_NAME}"
      ENV['GOO_PATH_DATA'] = "/repositories/#{JOB_NAME}/statements"
      ENV['GOO_PATH_UPDATE'] = "/repositories/#{JOB_NAME}/statements"
    elsif @options[:backend] == BACKEND_4STORE
      ENV['GOO_PATH_QUERY'] = '/sparql/'
      ENV['GOO_PATH_DATA'] = '/data/'
      ENV['GOO_PATH_UPDATE'] = '/update/'
    end
    resp = system("#{test_cmd}")
  rescue StandardError => e
    msg = "Failed test run with exception:\n\n#{e.class}: #{e.message}\n"
    puts msg
    puts e.backtrace
    resp = false
  end

  img_name = "#{@options[:backend]}-#{@options[:version]}-#{@options[:backend_port]}"
  img_name_redis = "redis-#{@options[:redis_port]}"
  rm_cmd = "docker rm -f -v #{img_name}; docker rm -f -v #{img_name_redis}"
  puts "\nRemoving Backend Docker Image: #{img_name}\n"
  puts "\nRemoving Redis Docker Image: #{img_name_redis}\n"
  %x(#{rm_cmd})
  exit(1) unless resp
end

def ag_rest_call(path, method)
  data = {}
  request = RestClient::Request.new(
      :method => method,
      :url => "http://#{GOO_HOST}:#{@options[:backend_port]}#{path}",
      :user => AG_USERNAME,
      :password => AG_PASSWORD,
      :headers => { :accept => :json, :content_type => :json }
  ).execute
  data = JSON.parse(response.to_str) if ['get', 'post'].include?(method.downcase)
  data
end

def parse_options
  backends = [BACKEND_4STORE.downcase, BACKEND_AG.downcase]
  options = {
      backend: BACKEND_4STORE,
      version: DEF_VERSION,
      filename: '',
      test: '',
      backend_port: -1,
      redis_port: 6379
  }
  opt_parser = OptionParser.new do |opts|
    opts.banner = "\n\s\s\s\s\sUsage: bundle exec ruby #{File.basename(__FILE__)} [options]\n\n"

    opts.on('-b', "--backend [#{BACKEND_4STORE}|#{BACKEND_AG}]", "An optional backend name. Default: #{BACKEND_4STORE}") do |bn|
      options[:backend] = bn.strip.downcase
    end

    opts.on('-v', '--version VERSION', "An optional version of the backend server to test against. Default: '#{DEF_VERSION}'\n\t\t\t\t\s\s\s\s\sMust be a valid image tag published on repositories:\n\t\t\t\t\thttps://hub.docker.com/r/bde2020/4store/tags for #{BACKEND_4STORE}\n\t\t\t\t\thttps://hub.docker.com/r/franzinc/agraph/tags for #{BACKEND_AG}") do |ver|
      options[:version] = ver.strip.downcase
    end

    opts.on('-p', '--backend_port PORT', "An optional port number of the backend server to test against. Default: #{DEF_4STORE_PORT} for #{BACKEND_4STORE}, #{DEF_AG_PORT} for #{BACKEND_AG}\n\t\t\t\t\s\s\s\s\sMust be a valid integer value") do |backend_port|
      options[:backend_port] = backend_port.strip.to_i
    end

    opts.on('-r', '--redis_port PORT', "An optional port number of the Redis server. Default: #{REDIS_PORT} \n\t\t\t\t\s\s\s\s\sMust be a valid integer value") do |redis_port|
      options[:redis_port] = redis_port.strip.to_i
    end

    opts.on('-f', '--file TEST_FILE_PATH', "An optional path to a test file to be run. Default: all test files") do |f|
      options[:filename] = f.strip
    end

    opts.on('-t', '--test TEST_NAME', "An optional name of the test to be run. Default: all tests") do |test|
      options[:test] = test.strip
    end

    opts.on('-h', '--help', 'Display this screen') do
      puts opts
      exit
    end
  end
  opt_parser.parse!
  options[:version] = "v#{options[:version]}" if options[:backend] == BACKEND_AG &&
                                                  options[:version] != DEF_VERSION &&
                                                  options[:version][0, 1].downcase != 'v'

  unless backends.include?(options[:backend].downcase)
    puts "\n#{options[:backend]} is not a valid backend. The valid backends are: [#{backends.join('|')}]"
    abort("Aborting...\n")
  end

  if options[:backend_port] == 0 || options[:redis_port] == 0
    puts "\nThe port number must be a valid integer. Run this script with the -h parameter for more information."
    abort("Aborting...\n")
  end
  options[:test] = '' if options[:filename].empty?
  options
end

main
