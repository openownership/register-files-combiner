module RegisterFilesCombiner
  class ExportFinalizer
    def initialize(s3_adapter: S3_ADAPTER, s3_bucket: S3_BUCKET)
      @s3_adapter = s3_adapter
      @s3_bucket = s3_bucket
    end

    def call(export_id)
      processed = false

      LOGGER.info "Checking export #{export_id} is ready"

      tmp_prefix = "bods_exports_tmp/export_id=#{export_id}"
      source_part_count1 = s3_adapter.list_objects(s3_bucket: s3_bucket, s3_prefix: tmp_prefix).length
      LOGGER.info "Export #{export_id} had #{source_part_count1} parts to extract"

      s3_prefix = "bods_exports_results/export_parts/export=#{export_id}"
      extract_part_count2 = s3_adapter.list_objects(s3_bucket: s3_bucket, s3_prefix: s3_prefix).length
      LOGGER.info "Export #{export_id} has extracted #{extract_part_count2} parts"

      if source_part_count1 == extract_part_count2
        LOGGER.info "Export #{export_id} is ready - starting to concatenate parts"

        dst_s3_location = "bods_exports_results/#{export_id}.jsonl.gz"

        LOGGER.info "Writing final export #{export_id} to #{dst_s3_location}"

        concat(s3_prefix, dst_s3_location)

        LOGGER.info "Completed writing final export #{export_id} to #{dst_s3_location}"

        processed = true
      else
        LOGGER.info "Export #{export_id} is not ready - try again later"
      end

      { export_id: export_id, processed: processed }
    end

    private

    attr_reader :s3_adapter, :s3_bucket

    def concat(s3_prefix, dest_path)
      upload_id = s3_adapter.create_multipart_upload(s3_bucket: s3_bucket, s3_path: dest_path)

      keys = s3_adapter.list_objects(s3_bucket: s3_bucket, s3_prefix: s3_prefix)
      part_limit = 100

      parts = []
      keys.sort.each_with_index do |key, index|
        break if index >= part_limit

        etag = s3_adapter.add_multipart_part(
          s3_bucket: s3_bucket,
          source_path: key,
          dest_path: dest_path,
          part_number: (index+1),
          upload_id: upload_id
        ).copy_part_result.etag

        parts << { etag: etag, part_number: (index+1) }
      end

      s3_adapter.complete_multipart_upload(s3_bucket: s3_bucket, s3_path: dest_path, upload_id: upload_id, parts: parts)
      true
    end
  end
end
