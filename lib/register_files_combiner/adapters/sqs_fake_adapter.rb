require 'digest'
require 'json'

module RegisterFilesCombiner
  module Adapters
    class SqsFakeAdapter
      DEFAULT_IDEMPOTENCY_TOKEN = 'idem-fake'.freeze

      class FakeQueue
        def initialize
          @queue_messages = {}
          @in_progress = {}
          @idempotency_tokens = {}
        end

        def delete_message(receipt_handle)
          queue_messages.delete receipt_handle
          in_progress.delete receipt_handle
        end

        def receive_messages(limit: 1)
          # TODO: requeue any old messages

          queue_messages.keys[0...limit].map do |key|
            content = queue_messages[key]
            in_progress[key] = content
            queue_messages.delete key

            {
              receipt_handle: key,
              content: JSON.parse(content),
            }
          end
        end

        def send_messages(messages, idempotency_token)
          return false if idempotency_tokens[idempotency_token]

          messages.each do |msg|
            queue_messages[msg[:id]] = msg[:message_body]
          end

          idempotency_tokens[idempotency_token] = true
        end

        private

        attr_reader :queue_messages, :in_progress, :idempotency_tokens
      end

      def initialize(**_kwargs)
        @queues = {}
      end

      def delete_message(queue_url, receipt_handle:)
        queue = find_or_create_queue(queue_url)
        queue.delete_message(receipt_handle)
      end

      def receive_messages(queue_url, limit: 1)
        queue = find_or_create_queue(queue_url)
        queue.receive_messages(limit: limit)
      end

      def send_messages(queue_url, messages:, idempotency_token: DEFAULT_IDEMPOTENCY_TOKEN)
        queue = find_or_create_queue(queue_url)

        msgs = messages.map do |content|
          content_json = content.to_json
          id = Digest::MD5.hexdigest("#{idempotency_token}::#{content_json}")[0...20]
          { id: id, message_body: content_json }
        end

        queue.send_messages(msgs, idempotency_token)
      end

      private

      attr_reader :queues

      def find_or_create_queue(queue_url)
        queues[queue_url] ||= FakeQueue.new
      end
    end
  end
end
