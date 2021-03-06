Gem::Specification.new do |s|
  s.name            = 'logstash-output-honeycomb_json_batch'
  s.version         = '0.3.0'
  s.licenses        = ['Apache-2.0']
  s.summary         = "This output lets you `POST` batches of events to the Honeycomb.io API endpoint"
  s.description     = "This gem is a Logstash plugin required to be installed on top of the Logstash core pipeline using $LS_HOME/bin/logstash-plugin install gemname. This gem is not a stand-alone program"
  s.authors         = ["Honeycomb"]
  s.email           = 'support@honeycomb.io'
  s.homepage        = "https://honeycomb.io"
  s.require_paths = ["lib"]

  # Files
  s.files = Dir['lib/**/*','spec/**/*','*.gemspec','*.md','CONTRIBUTORS','Gemfile','LICENSE','NOTICE.TXT']

  # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "output" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", ">= 1.60", "<= 2.99"
  s.add_runtime_dependency "logstash-mixin-http_client", ">= 2.2.1", "<= 5.2.0"

  s.add_development_dependency 'logstash-devutils'
end
