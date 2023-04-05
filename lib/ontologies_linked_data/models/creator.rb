require "ontologies_linked_data/models/creator_identifier"
require "ontologies_linked_data/models/affiliation"
require "ontologies_linked_data/models/title"

module LinkedData
  module Models
    class Creator < LinkedData::Models::Base
      # ECOPORTAL_LOGGER.debug(" ????? ontologies_linked_data: creator.rb ?????")
      model :creator, name_with: lambda { |c| uuid_uri_generator(c) }
      #attribute :nameType, default: lambda { |record| "Personal"}
      #attribute :creatorName
      attribute :nameType, default: lambda { |record| "Personal"}
      attribute :givenName
      attribute :familyName
      attribute :creatorName, enforce: [:existence]
      attribute :creatorIdentifiers, enforce: [:creator_identifier, :list]
      attribute :affiliations, enforce: [:affiliation, :list]
      
      embedded true
      embed :creatorIdentifiers, :affiliations

      def self.where(*match)
        #ECOPORTAL_LOGGER.debug("\n\n ONTOLOGIES_LINKED_DATA - models/creators-> self.where: match=#{match.inspect}")
        new_match=[]
        and_match=[]
        where_statement = Goo::Base::Where.new(self,*match)
        match.each do |match_item|
          new_match_item1 = {}
          match_item.each do |attribute, value|
            if ! value.is_a?(Array)
              #ECOPORTAL_LOGGER.debug("\n  > self.where:NOT ARRAY > attribute=#{attribute} - value= #{value}")
              new_match_item1[attribute.to_sym] = value
              new_match << new_match_item1
            end
          end
          where_statement = Goo::Base::Where.new(self,*new_match)
          
          match_item.each do |attribute, value|
            if value.is_a?(Array)
              #ECOPORTAL_LOGGER.debug("\n  > self.where:IS ARRAY > attribute=#{attribute} - value= #{value}")
              value.each do |v|
                new_match_item2 = {}
                new_match_item2[attribute.to_sym] = v
                where_statement = where_statement.and(new_match_item2)                
              end            
            end
          end
        end
        #ECOPORTAL_LOGGER.debug("\n    where_statement=#{where_statement.inspect} ")
        return where_statement
      end

      

      # def to_dataciteHash()
      #   begin
      #     # LOGGER.debug "\n\n ONTOLOGIES_LINKED_DATA - models/creators-> to_dataciteHash" 
      #     attr_hash = {}
      #     self.class.attributes.each do |key|
      #       value = self.instance_variable_get("@#{key}")
      #       case key.to_sym
      #       when :nameType,:givenName,:familyName
      #         attr_hash[key.to_sym] = value unless value.nil?
      #       when :creatorName
      #         attr_hash[:name] = value unless value.nil?
      #       when :creatorIdentifiers
      #         if !value.nil? && value.length>0
      #           attr_hash[:nameIdentifiers] = [] if attr_hash[:nameIdentifiers].nil?
      #           value.each do |e|
      #             attr_hash[:nameIdentifiers] << e.to_dataciteHash()
      #           end
      #         end
      #       when :affiliations
      #         if !value.nil? && value.length>0
      #           attr_hash[:affiliation] = [] if attr_hash[:affiliation].nil?
      #           value.each do |e|
      #             attr_hash[:affiliation] << e.to_dataciteHash()
      #           end
      #         end             
      #       end
      #       #end
      #       # attr_hash[attr]=v unless v.nil?
      #     end
      #     return attr_hash
      #   rescue => e
      #     LOGGER.debug "\n\n\nONTOLOGIES_LINKED_DATA - models/creators-> to_dataciteHash - ECCEZIONE: #{e.message}\n#{e.backtrace.join("\n")}"
      #     raise e        
      #   end
      # end
    
    end
  end
end
