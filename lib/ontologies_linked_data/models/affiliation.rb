module LinkedData
  module Models
    class Affiliation < LinkedData::Models::Base
      # ECOPORTAL_LOGGER.debug("\n\n ontologies_linked_data: affiliation.rb ?????")
      model :affiliation, name_with: lambda { |cc| uuid_uri_generator(cc) }
      attribute :affiliationIdentifierScheme, enforce: [:existence]
      attribute :affiliationIdentifier, enforce: [:existence]
      attribute :affiliation, enforce: [:existence]
      
      embedded true

    end
  end
end
