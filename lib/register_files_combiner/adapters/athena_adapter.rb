require 'aws-sdk-athena'

module RegisterFilesCombiner
  module Adapters
    class AthenaAdapter
      QueryTimeout = Class.new(StandardError)

      def initialize(region:, access_key_id:, secret_access_key:)
        @client = Aws::Athena::Client.new(
          region: region,
          access_key_id: access_key_id,
          secret_access_key: secret_access_key
        )
      end

      def get_query_execution(execution_id)
        client.get_query_execution({
          query_execution_id: execution_id
        })
      end

      def start_query_execution(params)
        client.start_query_execution(params)
      end

      def wait_for_query(execution_id, max_time: 100, wait_interval: 5)
        max_time.times do
          query = get_query_execution(execution_id)
          if query.query_execution.status.state == 'SUCCEEDED'
            return query
          end
          sleep wait_interval
        end

        raise QueryTimeout
      end

      private

      attr_reader :client
    end
  end
end
