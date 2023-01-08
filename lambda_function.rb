load_paths = Dir['./vendor/bundle/ruby/2.7.0/bundler/gems/**/lib']
$LOAD_PATH.unshift(*load_paths)

require 'json'
require_relative './lib/register_files_combiner'
require_relative './lib/register_files_combiner/step_reducer'
require_relative './lib/register_files_combiner/export_finalizer'
require_relative './lib/register_files_combiner/result_extractor'

def process_event_body(body)
  RegisterFilesCombiner::LOGGER.info "Processing event: #{body}"

  case body['msg_type']
  when "REDUCE_RESULTS"
    export_id = body.fetch 'export_id'
    RegisterFilesCombiner::StepReducer.new.call(export_id, 'results')
  when "FINALIZE_EXPORT"
    export_id = body.fetch 'export_id'
    RegisterFilesCombiner::ExportFinalizer.new.call(export_id)
  when "QUEUE_EXTRACT"
    export_id = body.fetch 'export_id'
    RegisterFilesCombiner::ResultExtractor.new.queue_extract(export_id)
  when "EXTRACT_PART"
    export_id = body.fetch 'export_id'
    s3_path = body.fetch 's3_path'
    RegisterFilesCombiner::ResultExtractor.new.extract_part(export_id, s3_path)
  else
    raise 'unknown message type'
  end
end

def lambda_handler(event:, context:)
    response =
      if event['Records']
        event['Records'].map do |record|
          body = JSON.parse(record['body'])
          process_event_body body
        end
      else
        process_event_body event
      end

    { statusCode: 200, body: response }
end
