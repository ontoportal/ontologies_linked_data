module LinkedData
  module Models
    class CreatorIdentifier < LinkedData::Models::Base
      # ECOPORTAL_LOGGER.debug("")
      model :creator_identifier, name_with: lambda { |cc| uuid_uri_generator(cc) }
      attribute :nameIdentifierScheme, enforce: [:existence]
      attribute :schemeURI, enforce: [:existence]
      attribute :nameIdentifier, enforce: [:existence]
      
      embedded true

    end
  end
end
