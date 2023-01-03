module RegisterFilesCombiner
  class StepReducer
    def initialize(
      s3_bucket:        S3_BUCKET,
      s3_prefix:        S3_PREFIX,
      athena_adapter:   ATHENA_ADAPTER,
      athena_database:  ENV.fetch('ATHENA_DATABASE'),
      bods_export_table: ENV.fetch('ATHENA_TABLE_NAME')
    )
      @athena_adapter  = athena_adapter
      @athena_database = athena_database
      @s3_bucket       = s3_bucket
      @s3_prefix       = s3_prefix
      @output_location = "s3://#{s3_bucket}/athena_results"
      @bods_export_table = bods_export_table
    end

    def call(export_id, dest_prefix)
      repair_table(bods_export_table)

      tmp_s3_prefix = "bods_exports_tmp/export_id=#{export_id}"
      execution = final_reduce(export_id, tmp_s3_prefix)
      athena_adapter.wait_for_query(execution.query_execution_id)

      { export_id: export_id }
    end

    private

    attr_reader :s3_bucket, :athena_database, :athena_adapter, :bods_export_table, :output_location

    def repair_table(table_name)
      athena_query = athena_adapter.start_query_execution({
        query_string: "MSCK REPAIR TABLE #{athena_database}.#{table_name}",
        result_configuration: {
          output_location: output_location
        }
      })
      athena_adapter.wait_for_query(athena_query.query_execution_id)
    end

    def final_reduce(export_id, tmp_s3_prefix)
      tmp_s3_location = "s3://#{s3_bucket}/#{tmp_s3_prefix}"

      query = <<~SQL
        CREATE TABLE #{athena_database}.bods_export_tmp_#{export_id}_parts
        WITH (
          external_location = '#{tmp_s3_location}',
          write_compression = 'GZIP',
          format = 'TEXTFILE',
          bucketed_by = ARRAY['content'],
          bucket_count = 1,
          partitioned_by = ARRAY['part_id']
        ) AS
          SELECT
            fname,
            row_i,
            content,
            part_id
          FROM (
            SELECT
              content,
              part_id,
              fname,
              row_i,
              rank() OVER (PARTITION BY statementID ORDER BY part_id, fname, row_i) AS row_r
            FROM
              (
                SELECT
                  CAST(json_extract(content, '$.statementID') AS VARCHAR) AS statementID,
                  "$path" AS fname,
                  ('part-' || "year" || '-' || "month" || '-' || "day") AS part_id,
                  row_number() OVER (PARTITION BY "$path") AS row_i,
                  content
                FROM
                  #{athena_database}.#{bods_export_table}
              ) x
          ) y
          WHERE
            y.row_r = 1
          ORDER BY
            fname ASC, row_i ASC    
      SQL

      LOGGER.info "EXECUTING QUERY: #{query}"
      athena_adapter.start_query_execution({
        query_string: query,
        client_request_token: Digest::MD5.hexdigest(query)[0...32],
        result_configuration: {
          output_location: output_location
        }
      })
    end
  end
end
