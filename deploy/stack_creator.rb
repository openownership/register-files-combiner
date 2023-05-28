require 'digest'
require 'logger'
require_relative 'stack'

require 'aws-sdk-athena'
require 'aws-sdk-iam'
require 'aws-sdk-lambda'
require 'aws-sdk-s3'
require 'aws-sdk-sqs'
require 'aws-sdk-states'

class StackCreator
  def initialize(region:, account_id:, access_key_id:, secret_access_key:)
    @logger = Logger.new($stdout)

    auth = {
      region: region,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
    }

    @aws_region = region
    @aws_account_id = account_id
    @athena_client = Aws::Athena::Client.new(**auth)
    @iam_client = Aws::IAM::Client.new(**auth)
    @lambda_client = Aws::Lambda::Client.new(**auth)
    @s3_client = Aws::S3::Client.new(**auth)
    @sqs_client = Aws::SQS::Client.new(**auth)
    @step_function_client = Aws::States::Client.new(**auth)
  end

  # TODO: adding logging, ARN to stacks, script file to call it
  def call(name, _env)
    stack = Stack.new(name, aws_region: aws_region, account_id: aws_account_id)

    # create resources
    create_s3_bucket stack
    create_extraction_sqs_queue stack
    create_athena_table stack

    # create lambda functions
    create_orchestration_lambda stack

    # create step function
    create_step_function stack
  end

  private

  attr_reader :logger, :athena_client, :iam_client, :lambda_client, :s3_client, :sqs_client,
              :step_function_client, :aws_region, :aws_account_id

  def create_s3_bucket(stack)
    # TODO: disable public objects
    logger.info "Creating S3 Bucket #{stack.bucket_name}"
    resp = s3_client.create_bucket(
      bucket: stack.bucket_name,
    )
    logger.info "Response #{resp.to_h}"
    logger.info "Waiting for bucket to exist..."

    s3_client.wait_until(:bucket_exists, { bucket: stack.bucket_name })

    logger.info "S3 Bucket created successfully"
  end

  def create_extraction_sqs_queue(stack)
    logger.info "Creating SQS Queue #{stack.extraction_sqs_queue_name}"

    resp = sqs_client.create_queue(
      {
        queue_name: stack.extraction_sqs_queue_name,
        attributes: {
          "VisibilityTimeout" => "1200", # 20 minutes
        },
      },
    )

    logger.info "Response #{resp.to_h}"
    logger.info "Waiting for SQS queue to exist..."

    sleep 5 # TODO: check created

    logger.info "SQS queue created successfully"
  end

  # Setup Athena

  def create_athena_table(stack)
    logger.info "Creating Athena Database #{stack.athena_database}"

    ddl_command = "CREATE DATABASE #{stack.athena_database}"
    execute_athena_query(stack, ddl_command)

    logger.info "Creating Athena Table #{stack.athena_table_name}"

    ddl_command = <<~SQL
      CREATE EXTERNAL TABLE `#{stack.athena_database}.#{stack.athena_table_name}`(
        `content` string)
      PARTITIONED BY (#{' '}
        `source` string,#{' '}
        `year` string,
        `month` string,
        `day` string)
      ROW FORMAT DELIMITED#{' '}
        FIELDS TERMINATED BY '\u0001'#{' '}
        LINES TERMINATED BY '\n'#{' '}
      STORED AS INPUTFORMAT#{' '}
        'org.apache.hadoop.mapred.TextInputFormat'#{' '}
      OUTPUTFORMAT#{' '}
        'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
      LOCATION
        's3://#{stack.bucket_name}/#{stack.s3_parts_path}'
      TBLPROPERTIES (
        'has_encrypted_data'='false'
      )
    SQL
    execute_athena_query(stack, ddl_command)

    logger.info "Athena table created successfully"
  end

  def execute_athena_query(stack, query)
    output_location = "s3://#{stack.bucket_name}/athena_queries"
    execution = athena_client.start_query_execution(
      query_string: query,
      client_request_token: Digest::MD5.hexdigest(query)[0...32],
      result_configuration: {
        output_location: output_location,
      },
    )
    20.times do
      query = athena_client.get_query_execution(
        query_execution_id: execution.query_execution_id,
      )
      if query.query_execution.status.state == 'SUCCEEDED'
        return query
      end

      sleep 3
    end

    raise QueryTimeout
  end

  # Setup Lambda Functions

  def create_orchestration_lambda(stack)
    # Create IAM role for lambda function
    logger.info "Creating role: #{stack.orchestration_function_role_name}"
    role = iam_client.create_role(
      {
        assume_role_policy_document: {
          Version: "2012-10-17",
          Statement: [
            {
              Effect: "Allow",
              Principal: {
                Service: "lambda.amazonaws.com",
              },
              Action: "sts:AssumeRole",
            },
          ],
        }.to_json,
        path: '/',
        role_name: stack.orchestration_function_role_name,
      },
    )
    logger.info "Resp #{role.to_h}"
    logger.info "Waiting for role to be created..."
    iam_client.wait_until(
      :role_exists,
      { role_name: stack.orchestration_function_role_name },
    )
    logger.info "Role created successfully"

    # Create Policy
    resp = iam_client.create_policy(
      {
        policy_name: stack.orchestration_function_policy_name,
        policy_document: orchestration_lambda_policy(stack).to_json,
      },
    )
    logger.info "Resp #{resp.to_h}"
    logger.info "Awaiting for policy to be created"
    policy_arn = resp.policy.arn
    iam_client.wait_until(
      :policy_exists,
      { policy_arn: policy_arn },
    )
    logger.info "Policy created successfully"

    # Attach Policy to Role
    logger.info "Attaching policy to role"
    iam_client.attach_role_policy(
      {
        role_name: stack.orchestration_function_role_name,
        policy_arn: policy_arn,
      },
    )
    logger.info "Attached policy to role"

    role_arn = role.role.arn

    logger.info "Sleeping 10 seconds until role is ready"
    sleep 10

    # Create Function
    logger.info "Creating function: #{stack.orchestration_function_name}"
    resp = lambda_client.create_function(
      description: "Register Export Orchestration",
      environment: {
        variables: stack.orchestration_env_variables,
      },
      code: {
        s3_bucket: 'oo-register-dev', # dummy function
        s3_key: "code/register_files_combiner_main.zip", # dummy code
      },
      function_name: stack.orchestration_function_name,
      handler: "lambda_function.lambda_handler",
      memory_size: 9000,
      publish: true,
      role: role_arn,
      runtime: 'ruby2.7',
      timeout: 850,
    )
    logger.info "Response: #{resp.to_h}"
    logger.info "Waiting for function to exist..."
    lambda_client.wait_until(
      :function_exists,
      { function_name: stack.orchestration_function_name },
    )
    logger.info "Lambda function created successfully"

    # Set function concurrency
    logger.info "Updating function concurrency"
    resp = lambda_client.put_function_concurrency(
      function_name: stack.orchestration_function_name,
      reserved_concurrent_executions: 25,
    )
    logger.info "Response #{resp.to_h}"
    logger.info "Waiting for function to be updated"
    lambda_client.wait_until(
      :function_updated,
      { function_name: stack.orchestration_function_name },
    )

    # Create SQS trigger
    logger.info "Creating SQS trigger for function"
    queue_arn = stack.extraction_sqs_queue_arn
    lambda_client.create_event_source_mapping(
      event_source_arn: queue_arn,
      function_name: stack.orchestration_function_name,
      enabled: true,
      batch_size: 1,
    )
    logger.info "Waiting for function to be updated"
    lambda_client.wait_until(
      :function_updated,
      { function_name: stack.orchestration_function_name },
    )
    logger.info "Function updated successfully"
    logger.info "Function creation completed successfully"
  end

  def create_step_function(stack)
    # Create Role
    logger.info "Creating role #{stack.step_function_role_name}"
    resp = iam_client.create_role(
      {
        assume_role_policy_document: {
          Version: "2012-10-17",
          Statement: [
            {
              Effect: "Allow",
              Principal: {
                Service: "states.amazonaws.com",
              },
              Action: "sts:AssumeRole",
            },
          ],
        }.to_json,
        path: '/',
        role_name: stack.step_function_role_name,
      },
    )
    role_arn = resp.role.arn
    logger.info "Response #{resp.to_h}"

    # Create Policy
    resp = iam_client.create_policy(
      {
        policy_name: stack.step_function_policy_name,
        policy_document: step_function_policy(stack).to_json,
      },
    )
    logger.info "Resp #{resp.to_h}"
    logger.info "Awaiting for policy to be created"
    policy_arn = resp.policy.arn
    iam_client.wait_until(
      :policy_exists,
      { policy_arn: policy_arn },
    )
    logger.info "Policy created successfully"

    # Attach Policy to Role
    logger.info "Attaching policy to role"
    iam_client.attach_role_policy(
      {
        role_name: stack.step_function_role_name,
        policy_arn: policy_arn,
      },
    )
    logger.info "Attached policy to role"

    # Create Step function
    logger.info "Creating step function #{stack.step_function_role_name}"
    definition = create_step_function_definition(stack)
    resp = step_function_client.create_state_machine(
      name: stack.step_function_name,
      definition: definition.to_json,
      role_arn: role_arn,
      type: "STANDARD",
    )
    logger.info "Response #{resp.to_h}"
    logger.info "Step function created successfully"
  end

  # IAM Policy Definitions

  def orchestration_lambda_policy(_stack)
    {
      Version: "2012-10-17",
      Statement: [
        {
          Effect: "Allow",
          Action: [
            "sqs:ReceiveMessage",
            "sqs:DeleteMessage",
            "sqs:GetQueueAttributes",
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "athena:*",
            "sqs:*",
            "glue:*",
            "s3:*",
            "lambda:*",
            "dynamodb:*",
            "cloudwatch:PutMetricAlarm",
            "cloudwatch:DescribeAlarms",
            "cloudwatch:DeleteAlarms",
            "cloudformation:DescribeStacks",
            "cloudformation:ListStackResources",
            "cloudwatch:ListMetrics",
            "cloudwatch:GetMetricData",
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeSubnets",
            "ec2:DescribeVpcs",
            "kms:ListAliases",
            "iam:GetPolicy",
            "iam:GetPolicyVersion",
            "iam:GetRole",
            "iam:GetRolePolicy",
            "iam:ListAttachedRolePolicies",
            "iam:ListRolePolicies",
            "iam:ListRoles",
            "lambda:*",
            "logs:DescribeLogGroups",
            "states:DescribeStateMachine",
            "states:ListStateMachines",
            "tag:GetResources",
            "xray:GetTraceSummaries",
            "xray:BatchGetTraces",
          ],
          Resource: "*",
        },
        {
          Action: [
            "dynamodb:*",
            "dax:*",
            "application-autoscaling:*",
            "iam:GetRole",
            "iam:ListRoles",
            "kms:DescribeKey",
            "kms:ListAliases",
            "resource-groups:*",
            "tag:GetResources",
          ],
          Effect: "Allow",
          Resource: "*",
        },
        {
          Action: [
            "iam:PassRole",
          ],
          Effect: "Allow",
          Resource: "*",
          Condition: {
            StringLike: {
              'iam:PassedToService': [
                "application-autoscaling.amazonaws.com",
                "application-autoscaling.amazonaws.com.cn",
                "dax.amazonaws.com",
              ],
            },
          },
        },
        {
          Effect: "Allow",
          Action: [
            "iam:CreateServiceLinkedRole",
          ],
          Resource: "*",
          Condition: {
            StringEquals: {
              'iam:AWSServiceName': [
                "replication.dynamodb.amazonaws.com",
                "dax.amazonaws.com",
                "dynamodb.application-autoscaling.amazonaws.com",
                "contributorinsights.dynamodb.amazonaws.com",
              ],
            },
          },
        },
        {
          Effect: "Allow",
          Action: "iam:PassRole",
          Resource: "*",
          Condition: {
            StringEquals: {
              'iam:PassedToService': "lambda.amazonaws.com",
            },
          },
        },
      ],
    }
  end

  def processor_lambda_policy(stack)
    orchestration_lambda_policy(stack)
  end

  def step_function_policy(stack)
    {
      Version: "2012-10-17",
      Statement: [
        {
          Sid: "VisualEditor0",
          Effect: "Allow",
          Action: "lambda:InvokeFunction",
          Resource: stack.orchestration_function_arn,
        },
        {
          Sid: "VisualEditor1",
          Effect: "Allow",
          Action: "lambda:InvokeFunction",
          Resource: stack.orchestration_function_arn,
        },
        {
          Effect: "Allow",
          Action: [
            "xray:PutTraceSegments",
            "xray:PutTelemetryRecords",
            "xray:GetSamplingRules",
            "xray:GetSamplingTargets",
          ],
          Resource: [
            "*",
          ],
        },
      ],
    }
  end

  # Step Function Definition

  def create_step_function_definition(stack)
    {
      Comment: "A description of my state machine",
      StartAt: "Step Reducer Params",
      States: {
        'Step Reducer Params': {
          Type: "Pass",
          Result: "REDUCE_RESULTS",
          ResultPath: "$.msg_type",
          Next: "Step Reducer",
        },
        'Step Reducer': {
          Type: "Task",
          Resource: "arn:aws:states:::lambda:invoke",
          InputPath: "$",
          OutputPath: "$.Payload.body",
          ResultPath: "$",
          Parameters: {
            'Payload.$': "$",
            FunctionName: stack.orchestration_function_arn,
          },
          Retry: [
            {
              ErrorEquals: [
                "Lambda.ServiceException",
                "Lambda.AWSLambdaException",
                "Lambda.SdkClientException",
              ],
              IntervalSeconds: 2,
              MaxAttempts: 6,
              BackoffRate: 2,
            },
          ],
          Next: "Part Extractor Params",
        },
        'Part Extractor Params': {
          Type: "Pass",
          Result: "QUEUE_EXTRACT",
          ResultPath: "$.msg_type",
          Next: "Part Extractor",
        },
        'Part Extractor': {
          Type: "Task",
          Resource: "arn:aws:states:::lambda:invoke",
          InputPath: "$",
          OutputPath: "$.Payload.body",
          ResultPath: "$",
          Parameters: {
            'Payload.$': "$",
            FunctionName: stack.orchestration_function_arn,
          },
          Retry: [
            {
              ErrorEquals: [
                "Lambda.ServiceException",
                "Lambda.AWSLambdaException",
                "Lambda.SdkClientException",
              ],
              IntervalSeconds: 2,
              MaxAttempts: 6,
              BackoffRate: 2,
            },
          ],
          Next: "Export Finalizer Params",
        },
        'Export Finalizer Params': {
          Type: "Pass",
          Result: "FINALIZE_EXPORT",
          ResultPath: "$.msg_type",
          Next: "Export Finalizer",
        },
        'Export Finalizer': {
          Type: "Task",
          Resource: "arn:aws:states:::lambda:invoke",
          InputPath: "$",
          OutputPath: "$.Payload.body",
          ResultPath: "$",
          Parameters: {
            'Payload.$': "$",
            FunctionName: stack.orchestration_function_arn,
          },
          Retry: [
            {
              ErrorEquals: [
                "Lambda.ServiceException",
                "Lambda.AWSLambdaException",
                "Lambda.SdkClientException",
              ],
              IntervalSeconds: 2,
              MaxAttempts: 6,
              BackoffRate: 2,
            },
          ],
          Next: "Export Finalizer Choice",
        },
        'Export Finalizer Choice': {
          Type: "Choice",
          Choices: [
            {
              Not: {
                Variable: "$.processed",
                BooleanEquals: false,
              },
              Next: "SuccessState",
            },
          ],
          Default: "Export Finalizer Wait",
        },
        'Export Finalizer Wait': {
          Type: "Wait",
          Seconds: 30,
          Next: "Export Finalizer Params",
        },
        SuccessState: {
          Type: "Succeed",
        },
      },
    }
  end
end
