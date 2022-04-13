module LinkedData
  module Models
    module SKOS
      class Scheme < LinkedData::Models::Base

        model :scheme, name_with: :id, collection: :submission,
              namespace: :skos, schemaless: :true, rdf_type: lambda { |*x| RDF::SKOS[:ConceptScheme] }

        attribute :prefLabel, namespace: :skos, enforce: [:existence]

        attribute :submission, collection: lambda { |s| s.resource_id }, namespace: :metadata

        serialize_never :submission, :id
        serialize_methods :properties

        cache_timeout 14400

        def properties
          self.unmapped
        end

      end
    end
  end

end
