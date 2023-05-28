# frozen_string_literal: true

RSpec.describe RegisterFilesCombiner do
  it "has a version number" do
    expect(RegisterFilesCombiner::VERSION).not_to be_nil
  end

  describe 'JSON parser' do
    context 'when hash has an "&" symbol' do
      it 'escapes with unicode' do
        expect({ a: 'b & c' }.to_json).to eq(
          '{"a":"b \\u0026 c"}',
        )
      end
    end

    context 'when hash contains a Time' do
      it 'converts with defined precision' do
        expect({ d: Time.zone.at(1_642_722_675) }.to_json).to eq(
          '{"d":"2022-01-20T23:51:15.000Z"}',
        )
      end
    end
  end
end
