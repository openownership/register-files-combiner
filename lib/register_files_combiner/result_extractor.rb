require 'stringio'
require 'zlib'

module RegisterFilesCombiner
  class ResultExtractor
    def initialize(
      s3_adapter:  S3_ADAPTER,
      s3_bucket:   S3_BUCKET,  
      sqs_adapter: SQS_ADAPTER,
      queue_url:   POST_PROCESS_QUEUE_URL
    )
      @s3_adapter = s3_adapter
      @s3_bucket = s3_bucket
      @sqs_adapter = sqs_adapter
      @queue_url = queue_url
    end

    def queue_extract(export_id)
      tmp_s3_prefix = "bods_exports_tmp/export_id=#{export_id}"
      keys = s3_adapter.list_objects(s3_bucket: s3_bucket, s3_prefix: tmp_s3_prefix)

      keys.each do |s3_path|
        messages = [
          {
            msg_type:  'EXTRACT_PART',
            export_id: export_id,
            s3_path:   s3_path
          }
        ]
        LOGGER.info "Queueing #{s3_path}"

        sqs_adapter.send_messages(queue_url, messages: messages)
      end

      { export_id: export_id }
    end

    def extract_part(export_id, s3_path)
      part_match = /part_id=part(?<part_id>[\d-]+)/.match(s3_path)
      raise 'no part' unless part_match
      part_id = "part#{part_match[:part_id]}"

      dst_s3_prefix = "bods_exports_results"
      dst_s3_location = File.join(dst_s3_prefix, "export_parts/export=#{export_id}/#{part_id}.jsonl.gz")

      LOGGER.info "Downloading #{s3_path}"
      content = s3_adapter.download_from_s3_to_memory(s3_bucket: s3_bucket, s3_path: s3_path)

      gz = Zlib::GzipWriter.new(StringIO.new)

      LOGGER.info "Processing #{s3_path}"
      gz_reader = Zlib::GzipReader.new(content)
      gz_reader.each_line do |line|
        statement = line.split("\001")[2]
        gz.write statement
      end
      gz_reader.close
      LOGGER.info "Processed #{s3_path}"

      LOGGER.info "Finalizing gzip"
      result = StringIO.open(gz.close.string)

      LOGGER.info "Uploading result"
      s3_adapter.upload_from_file_obj_to_s3(s3_bucket: s3_bucket, s3_path: dst_s3_location, stream: result)
      result.close
      LOGGER.info "Uploaded gzip"

      true
    end

    private

    attr_reader :s3_adapter, :s3_bucket, :sqs_adapter, :queue_url
  end
end
