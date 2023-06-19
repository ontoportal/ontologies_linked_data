require_relative  './indentifier'

module LinkedData
  module Models
    # An agent (eg. person, group, software or physical artifact)
    class Agent < LinkedData::Models::Base

      model :Agent, namespace: :foaf, name_with: lambda { |cc| uuid_uri_generator(cc) }
      attribute :agentType, enforce: [:existence], enforcedValues: %w[person organization]
      attribute :name, namespace: :foaf, enforce: %i[existence unique]

      attribute :homepage, namespace: :foaf
      attribute :acronym, namespace: :skos, property: :altLabel
      attribute :email, namespace: :foaf, property: :mbox

      attribute :identifiers, namespace: :adms, property: :identifier, enforce: %i[Identifier list]
      attribute :affiliations, enforce: %i[Agent list is_organization]
      attribute :creator, type: :user, enforce: [:existence]

      embed :identifiers, :affiliations
      embed_values affiliations: LinkedData::Models::Agent.goo_attrs_to_load + [identifiers: LinkedData::Models::AgentIdentifier.goo_attrs_to_load]

      write_access :creator
      access_control_load :creator


      def is_organization(inst, attr)
        inst.bring(attr) if inst.bring?(attr)
        affiliations = inst.send(attr)

        Array(affiliations).each do |aff|
          return  [:is_organization, "`affiliations` must contain only agents of type Organization"] unless aff.agentType&.eql?('organization')
        end

        return []
      end
    end
  end
end
