require 'register_files_combiner/step_processing/mappers/create_relationships_for_statements'

RSpec.describe RegisterFilesCombiner::StepProcessing::Mappers::CreateRelationshipsForStatements do
  subject { described_class.new }

  let(:entity_id) { BSON::ObjectId('5ca49242b51e4f000403da6b') }

  context 'when source has statements' do
    let(:statement1) do
      RegisterFilesCombiner::Structs::Statement.new({
        _id:        BSON::ObjectId('5ca49242b51e4f000403da6c'),
        created_at: Time.parse("2013-12-01"),
        date:       Time.parse("2013-12-02"),
        ended_date: Time.parse("2013-12-03"),
        entity_id:  entity_id,
        name:       'statement1',
        type:       'type1',
        updated_at: Time.parse("2013-12-04")
      })
    end

    let(:statement2) do
      RegisterFilesCombiner::Structs::Statement.new({
        _id:        BSON::ObjectId('5ca49242b51e4f000403da6d'),
        created_at: Time.parse("2013-11-01"),
        date:       Time.parse("2013-11-02"),
        ended_date: Time.parse("2013-11-03"),
        entity_id:  entity_id,
        name:       'statement2',
        type:       'type2',
        updated_at: Time.parse("2013-11-04")
      })
    end

    let(:entity) do
      RegisterFilesCombiner::Structs::Entity.new({
        _id:             entity_id,
        self_updated_at: Time.parse("2013-12-13")
      })
    end

    before do
      statement1.entity = entity
      statement2.entity = entity
      entity.statements = [statement1, statement2]
    end

    it 'creates a relationship for each associated statement' do
      relationships = subject.call(entity)

      # Creates a relationship per statement
      expect(relationships.length).to eq entity.statements.length

      # Expectations for relationship1
      relationship1 = relationships[0]
      expect(relationship1.source).to be_a RegisterFilesCombiner::Structs::UnknownPersonsEntity
      expect(relationship1.source_id).to eq relationship1.source.id
      expect(relationship1.target).to eq entity
      expect(relationship1.target_id).to eq entity.id
      expect(relationship1.id).to eq({
        'document_id' => 'OpenOwnership Register',
        'statement_id' => statement1.id,
      })
      expect(relationship1.ended_date).to eq statement1.ended_date
      expect(relationship1.ended_date).to eq statement1.ended_date

      # Expectations for relationship2
      relationship2 = relationships[1]
      expect(relationship2.source).to be_a RegisterFilesCombiner::Structs::UnknownPersonsEntity
      expect(relationship2.source_id).to eq relationship2.source.id
      expect(relationship2.target).to eq entity
      expect(relationship2.target_id).to eq entity.id
      expect(relationship2.id).to eq({
        'document_id' => 'OpenOwnership Register',
        'statement_id' => statement2.id,
      })
      expect(relationship2.ended_date).to eq statement2.ended_date
      expect(relationship2.ended_date).to eq statement2.ended_date
    end
  end
end
