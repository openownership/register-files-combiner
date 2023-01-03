require 'register_files_combiner/step_processing/mappers/identifiers'

RSpec.describe RegisterFilesCombiner::StepProcessing::Mappers::Identifiers do
  subject { described_class.new }

  describe '#map_identifiers' do
    let(:entity_id) { 'abcdefg' }
    let(:entity) do
      RegisterFilesCombiner::Structs::Entity.new(
        {
          _id: entity_id,
          type: entity_type,
          identifiers: [
            {
              jurisdiction_code: 'GB',
              company_number: 212
            },
            {
              link: 'l12',
              document_id: 'GB PSC Snapshot',
              company_number: 564
            },
            {
              jurisdiction_code: 'dk',
              document_id: 'Denmark CVR',
              uri: 'denmark-cvr-uri'
            },
            {
              jurisdiction_code: 'gb',
              document_id: 'Denmark CVR'
            }, # non-matching document_id
          ]
        }
      )
    end

    context 'when entity is legal_entity' do
      let(:entity_type) { RegisterFilesCombiner::Structs::Entity::Types::LEGAL_ENTITY }

      it 'returns correct identifiers' do
        result = subject.map_identifiers(entity)
        expect(result).to eq(
          [
            {
              id: "https://opencorporates.com/companies/GB/212",
              schemeName: "OpenCorporates",
              uri: "https://opencorporates.com/companies/GB/212"
            },
            {
              id: "l12",
              schemeName: "GB Persons Of Significant Control Register"
            },
            {
              id: 564,
              schemeName: "GB Persons Of Significant Control Register - Registration numbers"
            },
            {
              schemeName: "DK Centrale Virksomhedsregister",
              uri: 'denmark-cvr-uri'
            },
            {
              schemeName: "DK Centrale Virksomhedsregister",
            },
            {
              id: "http://register.openownership.org/entities/abcdefg",
              schemeName: "OpenOwnership Register",
              uri: "http://register.openownership.org/entities/abcdefg"
            }
          ]
        )
      end
    end
  end
end
