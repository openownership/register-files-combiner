require 'aws-sdk-sqs'

module RegisterFilesCombiner
  module Adapters
    class SqsAdapter
      DEFAULT_IDEMPOTENCY_TOKEN = 'idemp'

      def initialize(region:, access_key_id:, secret_access_key:)
        @client = Aws::SQS::Client.new(
          region: region,
          access_key_id: access_key_id,
          secret_access_key: secret_access_key,
        )
      end

      def delete_message(queue_url, receipt_handle:)
        client.delete_message({
          queue_url: queue_url,
          receipt_handle: receipt_handle
        })
      end

      def receive_messages(queue_url, limit: 1)
        queue = Aws::SQS::Queue.new(queue_url, client: client)

        collection = queue.receive_messages({
          attribute_names: ["All"],
          message_attribute_names: ["MessageAttributeName"],
          max_number_of_messages: limit,
          visibility_timeout: 1000,
          wait_time_seconds: 5
        })

        return [] if collection.size == 0
        
        collection.map do |message|
          {
            receipt_handle: message.receipt_handle,
            content: JSON.parse(message.body)
          }
        end
      end

      def send_messages(queue_url, messages:, idempotency_token: DEFAULT_IDEMPOTENCY_TOKEN)
        msgs = messages.map do |content|
          content_json = content.to_json
          id = Digest::MD5.hexdigest("#{idempotency_token}::#{content_json}")[0...20]
          { id: id, message_body: content_json }
        end

        client.send_message_batch({
          queue_url: queue_url,
          entries: msgs
        })
      end

      private

      attr_reader :client
    end
  end
end
