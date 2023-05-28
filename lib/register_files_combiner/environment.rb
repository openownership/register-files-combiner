require 'dotenv'

require 'register_common/structs/aws_credentials'
require 'register_common/adapters/athena_adapter'
require 'register_common/adapters/s3_adapter'

require_relative 'adapters/error_adapter'
require_relative 'adapters/sqs_adapter'

module RegisterFilesCombiner
  NotTestEnvError = Class.new(StandardError)

  class Environment
    DEVELOPMENT = 'development'.freeze
    TEST = 'test'.freeze
    PRODUCTION = 'production'.freeze

    def initialize(env_name: nil)
      @env_name = (env_name || get_env_name).to_s.downcase

      raise NotTestEnvError if RegisterFilesCombiner.const_defined?('UNITTEST') && (@env_name != TEST)

      load_env
    end

    def setup; end

    def logger
      return @logger if @logger

      @logger = Logger.new($stdout)
      @logger.level = Logger::DEBUG
      @logger
    end

    private

    attr_reader :env_name

    def get_env_name
      ENV.fetch('RACK_ENV', DEVELOPMENT)
    end

    def env_path
      case env_name
      when DEVELOPMENT
        '.env'
      when TEST
        '.test.env'
      when PRODUCTION
        '.production.env'
      else
        '.env'
      end
    end

    def load_env
      Dotenv.load(env_path)
    end
  end

  ENVIRONMENT = Environment.new
  ENVIRONMENT.setup

  # Initialize Logger

  LOGGER = ENVIRONMENT.logger

  # Initialize adapters

  AWS_AUTH = {
    access_key_id: ENV.fetch('BODS_EXPORT_AWS_ACCESS_KEY_ID', nil), # || ENV['AWS_ACCESS_KEY_ID'],
    secret_access_key: ENV.fetch('BODS_EXPORT_AWS_SECRET_ACCESS_KEY', nil), # || ENV['AWS_SECRET_ACCESS_KEY'],
    region: ENV.fetch('AWS_REGION', 'eu-west-1'),
  }.freeze
  AWS_CREDENTIALS = RegisterCommon::Structs::AwsCredentials.new(
    AWS_AUTH[:region],
    AWS_AUTH[:access_key_id],
    AWS_AUTH[:secret_access_key],
  )

  S3_ADAPTER = RegisterCommon::Adapters::S3Adapter.new(credentials: AWS_CREDENTIALS)
  SQS_ADAPTER = Adapters::SqsAdapter.new(**AWS_AUTH)
  ATHENA_ADAPTER = RegisterCommon::Adapters::AthenaAdapter.new(credentials: AWS_CREDENTIALS)
  ERROR_ADAPTER = Adapters::ErrorAdapter.new

  # Settings
  S3_BUCKET = ENV.fetch('BODS_EXPORT_S3_BUCKET_NAME', nil)
  QUEUE_URL = ENV.fetch('SQS_QUEUE_URL', nil)
  POST_PROCESS_QUEUE_URL = ENV.fetch('POST_PROCESS_QUEUE_URL', nil)
  S3_PREFIX = ENV.fetch('BODS_EXPORT_S3_PREFIX', "bods_exports_raw")
  CHUNK_SIZE = ENV.fetch('CHUNK_SIZE', 1000).to_i
  PART_SIZE = ENV.fetch('PART_SIZE', 500).to_i
end
