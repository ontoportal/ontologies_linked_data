module LinkedData
  module Models
    class OntologyType < LinkedData::Models::Base
      VALUES = [
          "ONTOLOGY",
          "VALUE_SET_COLLECTION"
      ]

      USER_READABLE = {
          "ONTOLOGY"             => "Ontology",
          "VALUE_SET_COLLECTION" => "Value Set Collection"
      }

      model :ontology_type, name_with: :code
      attribute :code, enforce: [:existence, :unique]
      attribute :ontologies,
                :inverse => { :on => :ontology, :attribute => :ontologyType }
      enum VALUES

      def get_code_from_id
        self.id.to_s.split("/")[-1]
      end

      def value_set_collection?
        code = get_code_from_id
        code === "VALUE_SET_COLLECTION"
      end

      def self.readable_types(types)
        types = where.models(types).include(:code).to_a.map {|s| s.code}
        types.sort! {|a,b| VALUES.index(a) <=> VALUES.index(b)}
        types.map {|t| USER_READABLE[t] || t.capitalize}
      end

      def ==(that)
        this_code = get_code_from_id
        if that.is_a?(String)
          # Assume it is a status code and work with it.
          that_code = that
        else
          return false unless that.is_a?(LinkedData::Models::OntologyType)
          that_code = that.get_code_from_id
        end
        return this_code == that_code
      end

    end
  end
end
