require "faraday"
require "faraday/multipart"

require_relative "openai/http"
require_relative "openai/client"
require_relative "openai/files"
require_relative "openai/finetunes"
require_relative "openai/images"
require_relative "openai/models"
require_relative "openai/assistants"
require_relative "openai/threads"
require_relative "openai/messages"
require_relative "openai/runs"
require_relative "openai/run_steps"
require_relative "openai/audio"
require_relative "openai/version"

module OpenAI
  class Error < StandardError; end
  class ConfigurationError < Error; end

  class MiddlewareErrors < Faraday::Middleware
    def call(env)
      @app.call(env)
    rescue Faraday::Error => e
      raise e unless e.response.is_a?(Hash)

      logger = Logger.new($stdout)
      logger.formatter = proc do |_severity, _datetime, _progname, msg|
        "\033[31mOpenAI HTTP Error (spotted in ruby-openai #{VERSION}): #{msg}\n\033[0m"
      end
      logger.error(e.response[:body])

      raise e
    end
  end

  class Configuration
    attr_reader :azure_token_provider
    attr_accessor :api_type, :api_version, :organization_id, :uri_base, :request_timeout,
                  :extra_headers, :access_token

    DEFAULT_API_VERSION = "v1".freeze
    DEFAULT_URI_BASE = "https://api.openai.com/".freeze
    DEFAULT_REQUEST_TIMEOUT = 120

    def initialize
      @access_token = nil
      @api_type = nil
      @api_version = DEFAULT_API_VERSION
      @organization_id = nil
      @uri_base = DEFAULT_URI_BASE
      @request_timeout = DEFAULT_REQUEST_TIMEOUT
      @extra_headers = {}
      @azure_token_provider = nil
    end

    def azure_token_provider=(provider)
      unless provider.nil? || provider.respond_to?(:to_proc)
        raise ConfigurationError,
              "OpenAI Azure AD token provider must be a Proc, Lambda, or respond to to_proc."
      end

      @azure_token_provider = provider&.to_proc
    end
  end

  class << self
    attr_writer :configuration
  end

  def self.configuration
    @configuration ||= OpenAI::Configuration.new
  end

  def self.configure
    yield(configuration)
  end

  # Estimate the number of tokens in a string, using the rules of thumb from OpenAI:
  # https://help.openai.com/en/articles/4936856-what-are-tokens-and-how-to-count-them
  def self.rough_token_count(content = "")
    raise ArgumentError, "rough_token_count requires a string" unless content.is_a? String
    return 0 if content.empty?

    count_by_chars = content.size / 4.0
    count_by_words = content.split.size * 4.0 / 3
    estimate = ((count_by_chars + count_by_words) / 2.0).round
    [1, estimate].max
  end
end
