require 'register_files_combiner/step_processing/mappers/statement_generator'

RSpec.describe RegisterFilesCombiner::StepProcessing::Mappers::StatementGenerator do
  subject do
    described_class.new(
      statement_id_calculator: statement_id_calculator,
      entity_statement_factory: entity_statement_factory,
      ownership_or_control_statement_factory: ownership_or_control_statement_factory,
      person_statement_factory: person_statement_factory
    )
  end

  let(:statement_id_calculator) { double 'statement_id_calculator' }
  let(:entity_statement_factory) { double 'entity_statement_factory' }
  let(:ownership_or_control_statement_factory) { double 'ownership_or_control_statement_factory' }
  let(:person_statement_factory) { double 'person_statement_factory' }

  let(:source1) { double 'source1', id: 'source1', legal_entity?: true, natural_person?: false }
  let(:source2) { double 'source2', id: 'source2', legal_entity?: false, natural_person?: true }
  let(:target1) { double 'target1', id: 'target1' }
  let(:target2) { double 'target2', id: 'target2' }
  let(:relationship1) { double('relationship1', source: source1, target: target1) }
  let(:relationship2) { double('relationship2', source: source2, target: target2) }

  let(:relationships) { [relationship1, relationship2] }
  let(:imports) { double 'imports' }

  describe '#call' do
    let(:source_statement1) { double 'source_statement1' }
    let(:source_statement2) { double 'source_statement2' }
    let(:target_statement1) { double 'target_statement1' }
    let(:target_statement2) { double 'target_statement2' }
    let(:relationship_statement1) { double 'relationship_statement1' }
    let(:relationship_statement2) { double 'relationship_statement2' }

    before do
      allow(statement_id_calculator).to receive(:generates_statement?).with(source1).and_return(true)
      allow(statement_id_calculator).to receive(:generates_statement?).with(source2).and_return(true)
      allow(entity_statement_factory).to receive(:call).with(source1).and_return(source_statement1)
      allow(person_statement_factory).to receive(:call).with(source2).and_return(source_statement2)
      allow(entity_statement_factory).to receive(:call).with(target1).and_return(target_statement1)
      allow(entity_statement_factory).to receive(:call).with(target2).and_return(target_statement2)
      allow(ownership_or_control_statement_factory).to receive(:call).with(relationship1, imports).and_return(
        relationship_statement1
      )
      allow(ownership_or_control_statement_factory).to receive(:call).with(relationship2, imports).and_return(
        relationship_statement2
      )
    end
  
    context 'when given relationships and imports' do
      it 'generates the statements' do
        statements = subject.call(relationships, imports)
        expect(statements).to eq([
          target_statement1,
          source_statement1,
          relationship_statement1,
          target_statement2,
          source_statement2,
          relationship_statement2
        ])
      end
    end

    context 'when relationships and imports are both empty' do
      let(:relationships) { [] }
      let(:imports) { {} }

      it 'returns an empty array' do
        statements = subject.call(relationships, imports)
        expect(statements).to be_empty
      end
    end

    context 'when entity occurs multiple times as source in relationships' do
      let(:relationship2) { double('relationship2', source: source1, target: target2) }

      it 'only writes a single entry for the generated source statement' do
        statements = subject.call(relationships, imports)
        expect(statements).to eq([
          target_statement1,
          source_statement1,
          relationship_statement1,
          target_statement2,
          relationship_statement2
        ])
      end
    end
    
    context 'when entity occurs multiple times as target in relationships' do
      let(:relationship2) { double('relationship2', source: source2, target: target1) }

      it 'only writes a single entry for the generated target statement' do
        statements = subject.call(relationships, imports)
        expect(statements).to eq([
          target_statement1,
          source_statement1,
          relationship_statement1,
          source_statement2,
          relationship_statement2
        ])
      end
    end

    context 'when source entry not generated' do
      let(:source3) { double 'source3', id: 'source3' }
      let(:relationship2) { double('relationship2', source: source3, target: target2) }

      before do
        allow(statement_id_calculator).to receive(:generates_statement?).with(source3).and_return(false)
      end

      it 'does not generate a statement for that source' do
        statements = subject.call(relationships, imports)
        expect(statements).to eq([
          target_statement1,
          source_statement1,
          relationship_statement1,
          target_statement2,
          relationship_statement2
        ])
      end
    end
  end
end
