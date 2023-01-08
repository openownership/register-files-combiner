class Stack
  PREFIX = 'register_bods_exporter'

  def initialize(name, aws_region:, account_id:)
    @name = name
    @aws_region = aws_region
    @account_id = account_id
  end

  attr_reader :name, :aws_region, :account_id

  def bucket_name
    "oo-register-bods-exporter-#{name}"
  end

  def athena_database
    "#{PREFIX}_#{name}"
  end

  def athena_table_name
    "bodsv2" # "#{PREFIX}_parts_#{name}"
  end

  def s3_parts_path
    'bods_data_dev'
  end

  def orchestration_function_role_name
    "#{PREFIX}_orchestration_#{name}_role"
  end

  def orchestration_env_variables
    { 'example' => 'env123' }
  end

  def orchestration_function_name
    "#{PREFIX}_orchestration_#{name}"
  end

  def step_function_role_name
    "#{PREFIX}_step_function_#{name}_role"
  end

  def orchestration_function_policy_name
    "#{PREFIX}_orchestration_#{name}_policy"
  end

  def step_function_policy_name
    "#{PREFIX}_step_function_#{name}_policy"
  end

  def orchestration_function_arn
    "arn:aws:lambda:#{aws_region}:#{account_id}:function:#{orchestration_function_name}"
  end

  def step_function_name
    "#{PREFIX}_#{name}"
  end

  def extraction_sqs_queue_name
    "#{PREFIX}_extraction_#{name}"
  end

  def extraction_sqs_queue_arn
    "arn:aws:sqs:#{aws_region}:#{account_id}:#{extraction_sqs_queue_name}"
  end

  def extraction_sqs_queue_url
    "https://sqs.#{aws_region}.amazonaws.com/#{account_id}/#{extraction_sqs_queue_name}"
  end
end
