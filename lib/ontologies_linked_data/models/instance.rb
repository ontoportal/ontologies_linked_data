
module LinkedData
  module Models
    class Instance < LinkedData::Models::Base

      model :named_individual, name_with: :id, collection: :submission,
            namespace: :owl, :schemaless => :true ,  rdf_type: lambda { |*x| RDF::OWL[:NamedIndividual]}


      attribute :label, namespace: :rdfs, enforce: [:list]
      attribute :prefLabel, namespace: :skos, enforce: [:existence], alias: true

      attribute :types, :namespace => :rdf, enforce: [:list], property: :type
      attribute :submission, :collection => lambda { |s| s.resource_id }, :namespace => :metadata

      serialize_never :submission, :id
      serialize_methods :properties

      cache_timeout 14400

      def properties
        self.unmapped
      end

    end
  end

  module InstanceLoader
    def self.count_instances_by_class(submission_id,class_id)
      ## TODO: pass directly an LinkedData::Models::OntologySubmission instance in the arguments instead of submission_id
      s = LinkedData::Models::OntologySubmission.find(submission_id).first
      self.instances_by_class_where_query(s,class_id).count
    end

    def self.get_instances_by_class(submission_id,class_id, page_no=1, size=50)
      ## TODO: pass directly an LinkedData::Models::OntologySubmission instance in the arguments instead of submission_id
      s = LinkedData::Models::OntologySubmission.find(submission_id).first

      inst = self.instances_by_class_where_query(s,class_id).page(page_no,size).all

      if inst.length > 0 # TODO test if "include=all" parameter is passed in the request
        self.load_unmapped s,inst # For getting all the properties # For getting all the properties
      end
    end


    def self.get_instances_by_ontology(submission_id,page_no=1,size=50)
      ## TODO: pass directly an LinkedData::Models::OntologySubmission instance in the arguments instead of submission_id
      s = LinkedData::Models::OntologySubmission.find(submission_id).first
      inst = s.nil? ? [] : self.instances_by_class_where_query(s).page(page_no,size).all

      if inst.length > 0 ## TODO test if "include=all" parameter is passed in the request
        self.load_unmapped s,inst # For getting all the properties
      end
    end

    private

    def self.instances_by_class_where_query(submission, class_id = nil )

      where_condition = class_id.nil? ? nil :{types: RDF::URI.new(class_id.to_s)}
      LinkedData::Models::Instance.where(where_condition).in(submission).include(:types)

    end

    def self.load_unmapped(submission, models)
      LinkedData::Models::Instance.where.in(submission).models(models).include(:unmapped).all
    end


  end
end
