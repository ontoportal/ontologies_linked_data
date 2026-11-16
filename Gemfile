source 'https://rubygems.org'

gem 'activesupport', '~> 8.1'
gem 'addressable', '~> 2.8'
gem 'bcrypt', '~> 3.0'
gem 'csv'
gem 'cube-ruby', require: 'cube'
gem 'faraday', '~> 1.9'
gem 'ffi'
gem 'libxml-ruby'
gem 'minitest'
gem 'multi_json', '~> 1.0'
gem 'oj'
gem 'omni_logger'
gem 'pony'
gem 'rack'
gem 'rack-test'
gem 'rake'
gem 'rest-client'
gem 'rsolr', '3.0.0'
gem 'rubyzip', '~> 3.0'
gem 'roo'
gem 'rdf-rdfxml'
gem 'thin'
gem 'request_store'
gem 'jwt'
gem 'json-ld', '~> 3.2.0'
gem "parallel", "~> 1.24"
gem 'rdf-raptor', github:'ruby-rdf/rdf-raptor', ref: '6392ceabf71c3233b0f7f0172f662bd4a22cd534' # use version 3.3.0 when available


# Testing
group :test do
  gem 'email_spec'
  gem 'minitest-reporters', '>= 0.5.0'
  gem 'ontoportal_testkit', github: 'agroportal/ontoportal_testkit', branch: 'main'
  gem 'pry'
  gem 'simplecov'
  gem 'simplecov-cobertura' # for codecov.io
  gem 'webmock'
end

group :development do
  gem 'rubocop', require: false
end
# NCBO gems (can be from a local dev path or from rubygems/git)
gem 'goo', github: 'agroportal/goo', branch: 'master'

gem 'net-ftp'
gem 'public_suffix', '~> 5.1.1'
gem 'net-imap', '~> 0.4.18'
