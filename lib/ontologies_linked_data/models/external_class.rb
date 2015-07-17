module LinkedData
  module Models
    class ExternalClass
      include LinkedData::Hypermedia::Resource
      # For class mapped to internal class that are outside any BioPortal appliance
      # We just generate a link to self class and a link to the external ontology

      attr_reader :id, :ontology, :type_uri

      serialize_never :id, :ontology, :type_uri

      link_to LinkedData::Hypermedia::Link.new("self", lambda {|ec| ec.id.to_s}, "http://www.w3.org/2002/07/owl#Class"),
              LinkedData::Hypermedia::Link.new("ontology", lambda {|ec| ec.ontology.to_s}, Goo.vocabulary["Ontology"])

      def initialize(id, ontology)
        @id = id
        @ontology = RDF::URI.new(CGI.unescape(ontology))
        @type_uri = RDF::URI.new("http://www.w3.org/2002/07/owl#Class")
      end
    end
  end
end