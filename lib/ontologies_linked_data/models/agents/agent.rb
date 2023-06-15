module LinkedData
  module Models
    # An agent (eg. person, group, software or physical artifact)
    class Agent < LinkedData::Models::Base

      model :Agent, namespace: :foaf, name_with: lambda { |cc| uuid_uri_generator(cc) }
      attribute :agentType, enforce: [:existence], enforcedValues: %w[person organization]
      attribute :name, namespace: :foaf, enforce: %i[existence unique]

      attribute :firstName, namespace: :foaf
      attribute :lastName, namespace: :foaf, property: :surname
      attribute :homepage, namespace: :foaf
      attribute :acronym, namespace: :skos, property: :altLabel
      attribute :email, namespace: :foaf, property: :mbox

      attribute :identifiers, namespace: :adms, property: :identifier, enforce: %i[Identifier list]
      attribute :affiliations, enforce: %i[Agent list]

      embed :identifiers, :affiliations
    end
  end
end
