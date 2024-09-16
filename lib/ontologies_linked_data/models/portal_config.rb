module LinkedData
  module Models
    class PortalConfig < LinkedData::Models::Base
      model :SemanticArtefactCatalogue, namespace: :mod, name_with: :acronym
      attribute :acronym, enforce: [:unique, :existence]
      attribute :title, namespace: :dcterms, enforce: [:existence]
      attribute :color, enforce: [:existence, :valid_hash_code]
      attribute :description, namespace: :dcterms
      attribute :logo, namespace: :foaf, enforce: [:url]
      attribute :numberOfArtefacts, namespace: :mod, handler: :ontologies_count
      attribute :federated_portals, handler: :federated_portals_settings
      attribute :fundedBy, namespace: :foaf, enforce: [:list]

      serialize_default :acronym, :title, :color, :description, :logo, :numberOfArtefacts, :federated_portals, :fundedBy

      def initialize(*args)
        super
        init_federated_portals_settings
      end

      def self.current_portal_config
        p = LinkedData::Models::PortalConfig.new

        p.acronym = LinkedData.settings.ui_name.downcase
        p.title = LinkedData.settings.title
        p.description = LinkedData.settings.description
        p.color = LinkedData.settings.color
        p.logo = LinkedData.settings.logo
        p.fundedBy = LinkedData.settings.fundedBy
        p
      end

      def init_federated_portals_settings(federated_portals = nil)
        @federated_portals = federated_portals || LinkedData.settings.federated_portals.symbolize_keys
      end

      def federated_portals_settings
        @federated_portals
      end

      def ontologies_count
        LinkedData::Models::Ontology.where(viewingRestriction: 'public').count
      end

      def self.valid_hash_code(inst, attr)
        inst.bring(attr) if inst.bring?(attr)
        str = inst.send(attr)

        return if (/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/ === str)
        [:valid_hash_code,
         "Invalid hex color code: '#{str}'. Please provide a valid hex code in the format '#FFF' or '#FFFFFF'."]
      end
    end
  end
end


