module LinkedData
  module Models
    # An agent (eg. person, group, software or physical artifact)
    class AgentIdentifier < LinkedData::Models::Base
      IDENTIFIER_SCHEMES = { ORCID: 'https://orcid.org', ISNI: 'https://isni.org/', ROR: 'https://ror.org/', GRID: 'https://www.grid.ac/' }.freeze

      model :Identifier, namespace: :adms, name_with: :notation

      attribute :notation, namespace: :skos, enforce: [:unique, :existence]
      attribute :schemaAgency, namespace: :adms, enforcedValues: IDENTIFIER_SCHEMES.keys, enforce: [:existence]
      attribute :schemeURI, handler: :scheme_uri_infer

      def scheme_uri_infer
        self.bring(:schemaAgency) if self.bring?(:schemaAgency)
        IDENTIFIER_SCHEMES[self.schemaAgency.to_sym] if self.schemaAgency
      end

    end

  end
end
