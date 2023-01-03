require 'register_files_combiner/adapters/sqs_fake_adapter'

RSpec.describe RegisterFilesCombiner::Adapters::SqsFakeAdapter do
  subject { described_class.new }

  let(:queue_url) { 'queue1' }
  let(:sample_message) do
    { 'test' => 1 }
  end
  let(:sample_message_receipt_handle) { '3bb83b8ae248ece68207' }

  # TODO: test with multiple queues

  describe '#delete_message' do
    context 'when message does not exist' do
      it 'does not error' do
        expect { subject.delete_message(queue_url, receipt_handle: 'abc') }.not_to raise_error
      end
    end

    context 'when message is in queue and has not started being processed' do
      before do
        subject.send_messages(queue_url, messages: [sample_message])
      end

      it 'removes the message' do
        subject.delete_message(queue_url, receipt_handle: sample_message_receipt_handle)

        messages = subject.receive_messages(queue_url)
        expect(messages).to be_empty
      end
    end
  end

  describe '#receive_messages' do
    context 'when queue is empty' do
      it 'returns an empty array' do
        messages = subject.receive_messages(queue_url)

        expect(messages).to be_empty
      end
    end

    context 'when all queues messages have started being processed' do
      before do
        subject.send_messages(queue_url, messages: [sample_message])
        subject.receive_messages(queue_url)
      end

      it 'returns an empty array' do
        messages = subject.receive_messages(queue_url)

        expect(messages).to be_empty
      end
    end

    context 'when queue has unprocessed messages' do
      before do
        subject.send_messages(queue_url, messages: [sample_message])
      end

      it 'returns unprocessed message' do
        messages = subject.receive_messages(queue_url)

        expect(messages).to eq([{
          content: sample_message,
          receipt_handle: sample_message_receipt_handle
        }])
      end
    end
  end

  describe '#send_messages' do
    context 'when sending a new message' do
      it 'adds message to queue' do
        messages = subject.receive_messages(queue_url)
        expect(messages).to be_empty

        subject.send_messages(queue_url, messages: [sample_message])

        messages = subject.receive_messages(queue_url)
        expect(messages).to eq([{
          content: sample_message,
          receipt_handle: sample_message_receipt_handle
        }])
      end
    end
  end
end
