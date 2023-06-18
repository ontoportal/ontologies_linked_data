module LinkedData
  module Models
    # An agent (eg. person, group, software or physical artifact)
    class AgentIdentifier < LinkedData::Models::Base
      IDENTIFIER_SCHEMES = { ORCID: 'https://orcid.org', ISNI: 'https://isni.org/', ROR: 'https://ror.org/', GRID: 'https://www.grid.ac/' }.freeze

      model :Identifier, namespace: :adms, name_with: :notation

      attribute :notation, namespace: :skos, enforce: %i[unique existence no_url]
      attribute :schemaAgency, namespace: :adms, enforcedValues: IDENTIFIER_SCHEMES.keys, enforce: [:existence]
      attribute :schemeURI, handler: :scheme_uri_infer
      attribute :creator, type: :user, enforce: [:existence]

      embedded true

      write_access :creator
      access_control_load :creator

      def self.no_url(inst,attr)
        inst.bring(attr) if inst.bring?(attr)
        notation = inst.send(attr)
        return  notation&.start_with?('http') ? [:no_url, "`notation` must not be a URL"]  : []
      end

      def scheme_uri_infer
        self.bring(:schemaAgency) if self.bring?(:schemaAgency)
        IDENTIFIER_SCHEMES[self.schemaAgency.to_sym] if self.schemaAgency
      end

    end

  end
end
