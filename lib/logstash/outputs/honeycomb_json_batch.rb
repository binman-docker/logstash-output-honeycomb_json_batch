# encoding: utf-8
require "logstash/outputs/base"
require "logstash/namespace"
require "logstash/json"
require "uri"
require "stud/buffer"
require "logstash/plugin_mixins/http_client"

class LogStash::Outputs::HoneycombJSONBatch < LogStash::Outputs::Base
  include LogStash::PluginMixins::HttpClient
  include Stud::Buffer

  config_name "honeycomb_json_batch"

  config :api_host, :validate => :string

  config :write_key, :validate => :string, :required => true

  config :dataset, :validate => :string, :required => true

  config :flush_size, :validate => :number, :default => 50

  config :idle_flush_time, :validate => :number, :default => 5

  config :retry_individual, :validate => :boolean, :default => true

  config :pool_max, :validate => :number, :default => 10

  def register
    # We count outstanding requests with this queue
    # This queue tracks the requests to create backpressure
    # When this queue is empty no new requests may be sent,
    # tokens must be added back by the client on success
    @request_tokens = SizedQueue.new(@pool_max)
    @pool_max.times {|t| @request_tokens << true }
    @total = 0
    @total_failed = 0
    @requests = Array.new
    if @api_host.nil?
      @api_host = "https://api.honeycomb.io"
    elsif !@api_host.start_with? "http"
      @api_host = "http://#{ @api_host }"
    end
    @api_host = @api_host.chomp

    buffer_initialize(
      :max_items => @flush_size,
      :max_interval => @idle_flush_time,
      :logger => @logger
    )
    logger.info("Initialized honeycomb_json_batch with settings",
      :flush_size => @flush_size,
      :idle_flush_time => @idle_flush_time,
      :request_tokens => @pool_max,
      :api_host => @api_host,
      :headers => request_headers,
      :retry_individual => @retry_individual)

  end

  # This module currently does not support parallel requests as that would circumvent the batching
  def receive(event, async_type=:background)
    buffer_receive(event)
  end

  def close
    buffer_flush(:final => true)
    client.close
  end

  public
  def flush(events, close=false)
    documents = []  #this is the array of hashes that we push to Fusion as documents

    events.each do |event|
      data = event.to_hash()
      timestamp = data.delete("@timestamp")
      doc = { "time" => timestamp, "data" => data }
      if samplerate = data.delete("@samplerate")
        doc["samplerate"] = samplerate.to_i
      end
      documents.push(doc)
    end

    make_request(documents)
  end

  def multi_receive(events)
    events.each {|event| buffer_receive(event)}
  end

  private

  def make_request(documents)
    body = LogStash::Json.dump({ @dataset => documents })
    # Block waiting for a token
    token = @request_tokens.pop
    @logger.debug("Got token", :tokens => @request_tokens.length)


    # Create an async request
    url = "#{@api_host}/1/batch"
    begin
      request = client.post(url, {
        :body => body,
        :headers => request_headers,
        :async => true
      })
    rescue Exception => e
      @logger.warn("An error occurred while indexing: #{e.message}")
    end

    # attach handlers before performing request
    request.on_complete do
      # Make sure we return the token to the pool
      @request_tokens << token
    end

    request.on_success do |response|
      if response.code >= 200 && response.code < 300
        @total = @total + documents.length
        @logger.debug("Successfully submitted",
          :docs => documents.length,
          :response_code => response.code,
          :total => @total)
      else
        if documents.length > 1 && @retry_individual
          if statuses = JSON.parse(response.body).values.first
            statuses.each_with_index do |status, i|
              code = status["status"]
              if code == nil
                @logger.warn("Status code missing in response: #{status}")
                next
              elsif code >= 200 && code < 300
                next
              end
              make_request([documents[i]])
            end
          end
        else
          @total_failed += documents.length
          log_failure(
              "Encountered non-200 HTTP code #{response.code}",
              :response_code => response.code,
              :url => url,
              :response_body => response.body,
              :num_docs => documents.length,
              :retry_individual => @retry_individual,
              :total_failed => @total_failed)
        end
      end
    end

    request.on_failure do |exception|
      @total_failed += documents.length
      log_failure("Could not access URL",
        :url => url,
        :method => @http_method,
        :body => body,
        :headers => request_headers,
        :message => exception.message,
        :class => exception.class.name,
        :backtrace => exception.backtrace,
        :total_failed => @total_failed
      )
    end

    client.execute!
  rescue Exception => e
    log_failure("Got totally unexpected exception #{e.message}", :docs => documents.length)
  end

  # This is split into a separate method mostly to help testing
  def log_failure(message, opts)
    @logger.error("[Honeycomb Batch Output Failure] #{message}", opts)
  end

  def request_headers()
    {
      "Content-Type" => "application/json",
      "X-Honeycomb-Team" => @write_key
    }
  end
end
