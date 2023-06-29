require_relative './identifier'

module LinkedData
  module Models
    # An agent (eg. person, group, software or physical artifact)
    class Agent < LinkedData::Models::Base

      model :Agent, namespace: :foaf, name_with: lambda { |cc| uuid_uri_generator(cc) }
      attribute :agentType, enforce: [:existence], enforcedValues: %w[person organization]
      attribute :name, namespace: :foaf, enforce: %i[existence]

      attribute :homepage, namespace: :foaf
      attribute :acronym, namespace: :skos, property: :altLabel
      attribute :email, namespace: :foaf, property: :mbox, enforce: %i[existence email unique]

      attribute :identifiers, namespace: :adms, property: :identifier, enforce: %i[Identifier list unique_identifiers]
      attribute :affiliations, enforce: %i[Agent list is_organization], namespace: :org, property: :memberOf
      attribute :creator, type: :user, enforce: [:existence]

      embed :identifiers, :affiliations
      embed_values affiliations: LinkedData::Models::Agent.goo_attrs_to_load + [identifiers: LinkedData::Models::AgentIdentifier.goo_attrs_to_load]

      write_access :creator
      access_control_load :creator


      def unique_identifiers(inst, attr)
        inst.bring(attr) if inst.bring?(attr)
        identifiers = inst.send(attr)
        return [] if identifiers.nil? || identifiers.empty?


        query =  LinkedData::Models::Agent.where(identifiers: identifiers.first)
        identifiers.drop(0).each do |i|
          query = query.or(identifiers: i)
        end
        existent_agents = query.include(:name).all
        existent_agents = existent_agents.reject{|a| a.id.eql?(inst.id)}
        return [:unique_identifiers, "`identifiers` already used by other agents: " + existent_agents.map{|x| x.name}.join(', ')] unless existent_agents.empty?
        []
      end
      def is_organization(inst, attr)
        inst.bring(attr) if inst.bring?(attr)
        affiliations = inst.send(attr)

        Array(affiliations).each do |aff|
          return  [:is_organization, "`affiliations` must contain only agents of type Organization"] unless aff.agentType&.eql?('organization')
        end

        []
      end
    end
  end
end
