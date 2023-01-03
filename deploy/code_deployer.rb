require 'logger'
require 'aws-sdk-lambda'
require 'aws-sdk-s3'

require_relative 'stack'

class CodeDeployer
  CmdError = Class.new(StandardError)

  def initialize(s3_bucket:, region:, access_key_id:, secret_access_key:, account_id:)
    @logger = Logger.new(STDOUT)
    @s3_bucket = s3_bucket
    @aws_region = region
    @aws_account_id = account_id

    auth = {
      region: region,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key
    }

    @lambda_client = Aws::Lambda::Client.new(**auth)
  end

  def call(stack_name, s3_path, env: {})
    stack = Stack.new(stack_name, aws_region: aws_region, account_id: aws_account_id)

    env_h = build_env(stack, env)

    deploy_orchestration_lambda(stack, s3_path, env_h)
  end

  private

  attr_reader :s3_bucket, :logger, :lambda_client, :aws_region, :aws_account_id

  def deploy_orchestration_lambda(stack, s3_path, env_h)
    logger.info "Updating orchestration lambda env"
    resp = lambda_client.update_function_configuration({
      function_name: stack.orchestration_function_name,
      environment: {
        variables: env_h
      }
    })
    logger.info "Response #{resp.to_h}"
    logger.info "Waiting for function to be updated"
    lambda_client.wait_until(
      :function_updated,
      { function_name: stack.orchestration_function_name }
    )
    logger.info "Function updated successfully"

    logger.info "Updating function code"
    resp = lambda_client.update_function_code(
      function_name: stack.orchestration_function_name,
      s3_bucket: s3_bucket, 
      s3_key: s3_path,
      publish: true,
      architectures: ["x86_64"]
    )
    logger.info "Response #{resp.to_h}"
    logger.info "Waiting for function to be updated"
    lambda_client.wait_until(
      :function_updated,
      { function_name: stack.orchestration_function_name }
    )
    logger.info "Function updated successfully"
  end

  def build_env(stack, env)
    env.merge(
      'BODS_EXPORT_S3_BUCKET_NAME' => stack.bucket_name,
      'ATHENA_DATABASE' => stack.athena_database,
      'POST_PROCESS_QUEUE_URL' => stack.extraction_sqs_queue_url,
      'BODS_EXPORT_S3_PREFIX' => stack.s3_parts_path,
      'ATHENA_TABLE_NAME' => stack.athena_table_name,
      'CHUNK_SIZE' => '1000',
      'PART_SIZE' => '500'
    )
  end
end
