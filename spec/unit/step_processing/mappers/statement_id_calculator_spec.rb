require 'register_files_combiner/step_processing/mappers/statement_id_calculator'

RSpec.describe RegisterFilesCombiner::StepProcessing::Mappers::StatementIdCalculator do
  subject { described_class.new }

  describe '#statement_id' do
    context 'when object is an Entity' do
      let(:_id) { BSON::ObjectId('5ca49242b51e4f000403da6b') }
      let(:self_updated_at) { Time.parse("2013-12-13") }
      let(:entity_params) do
        { _id: _id, self_updated_at: self_updated_at }
      end

      let(:expected_id) { 'openownership-register-8237614266131324284' }

      context 'with Entity known' do
        let(:entity) { RegisterFilesCombiner::Structs::Entity.new(entity_params) }

        it 'returns correct id' do
          expect(subject.statement_id(entity)).to eq expected_id
        end
      end

      context 'with Entity having unknown_reason_code which generates statement' do
        let(:entity) do
          RegisterFilesCombiner::Structs::UnknownPersonsEntity.new(
            entity_params.merge(
              unknown_reason_code: 'psc-contacted-but-no-response'
            )
          )
        end

        it 'returns correct id' do
          expect(subject.statement_id(entity)).to eq expected_id
        end
      end

      context 'with Entity having unknown_reason_code which does not generate statement' do
        let(:entity) do
          RegisterFilesCombiner::Structs::UnknownPersonsEntity.new(
            entity_params.merge(
              unknown_reason_code: 'unknown'
            )
          )
        end

        it 'returns nil' do
          expect(subject.statement_id(entity)).to be_nil
        end
      end
    end

    context 'when object is a Relationship' do
      let(:source_id) { BSON::ObjectId('5ca49242b51e4f000403da6b') }
      let(:target_id) { BSON::ObjectId('5ca49242b51e4f000403da6c') }
      let(:source_entity_params) do
        { _id: source_id, self_updated_at: Time.parse("2013-12-13") }
      end
      let(:target_entity_params) do
        { _id: target_id, self_updated_at: Time.parse("2013-12-14") }
      end
      let(:source) { RegisterFilesCombiner::Structs::Entity.new(source_entity_params) }
      let(:target) { RegisterFilesCombiner::Structs::Entity.new(target_entity_params) }

      let(:relationship) do
        r = RegisterFilesCombiner::Structs::Relationship.new({
          _id: {
            'relationship' => 'id' # TODO
          },
          updated_at: Time.parse("2013-12-15")
        })
        r.source = source
        r.target = target
        r
      end

      it 'returns correct id' do
        expect(subject.statement_id(relationship)).to eq 'openownership-register-14137434934398700630'
      end
    end

    context 'when object is a Statement' do
      let(:entity_params) do
        { _id: BSON::ObjectId('5ca49242b51e4f000403da6b'), self_updated_at: Time.parse("2013-12-13") }
      end
      let(:entity) { RegisterFilesCombiner::Structs::Entity.new(entity_params) }

      let(:statement) do
        s = RegisterFilesCombiner::Structs::Statement.new({
          _id: {
            'statement' => 'id' # TODO
          },
          updated_at: Time.parse("2013-12-15")
        })
        s.entity = entity
        s
      end

      it 'returns correct id' do
        expect(subject.statement_id(statement)).to eq 'openownership-register-13166592716358258966'
      end
    end

    context 'when object is an invalid type' do
      it 'raises an error' do
        expect { subject.statement_id('invalid_type') }.to raise_error(
          "Unexpected object for statement_id - class: String, obj: \"invalid_type\""
        )
      end
    end
  end
end
