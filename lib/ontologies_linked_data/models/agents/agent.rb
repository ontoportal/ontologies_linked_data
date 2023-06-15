module LinkedData
  module Models
    # An agent (eg. person, group, software or physical artifact)
    class Agent < LinkedData::Models::Base

      model :Agent, namespace: :foaf, name_with: :username
      attribute :type, enforce: [:existence], enforcedValues: %w[person organization]
      attribute :name, namespace: :foaf, enforce: [:existence]

      attribute :firstName, namespace: :foaf
      attribute :lastName, namespace: :foaf, property: :surname
      attribute :homepage, namespace: :foaf, property: :pageHome
      attribute :acronym, namespace: :skos, property: :altLabel
      attribute :email, namespace: :foaf, property: :mbox

      attribute :identifiers, namespace: :adms, property: :identifier, enforce: %i[Identifier list]
      attribute :affiliations, enforce: %i[Agent list]

      embed :identifiers, :affiliations
    end
  end
end
