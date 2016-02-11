module LinkedData
  module Models
    class ProvisionalClass < LinkedData::Models::Base
      model :provisional_class, name_with: lambda { |inst| uuid_uri_generator(inst) }

      attribute :label, enforce: [:existence]
      attribute :synonym, enforce: [:list]
      attribute :definition, enforce: [:list]
      attribute :subclassOf, enforce: [:uri]
      attribute :creator, enforce: [:existence, :user]
      attribute :created, enforce: [:date_time], :default => lambda { |record| DateTime.now }
      attribute :permanentId, enforce: [:uri]
      attribute :noteId, enforce: [:uri]
      attribute :ontology, enforce: [:ontology]

      attribute :relations,
                :inverse => { :on => :provisional_relation, :attribute => :source }

      search_options :index_id => lambda { |t| t.index_id },
                     :document => lambda { |t| t.index_doc }

      embed :relations

      # display relations and some search attributes by default
      serialize_default *(self.attributes.unshift(:prefLabel) << :relations << :obsolete << :matchType << :ontologyType << :provisional)

      link_to LinkedData::Hypermedia::Link.new("self", lambda {|s| "provisional_classes/#{CGI.escape(s.id.to_s)}"}, self.uri_type),
              LinkedData::Hypermedia::Link.new("ontology", lambda {|s| defined?(s.ontology) && s.ontology ? "ontologies/#{s.ontology.id.split('/')[-1]}" : defined?(s.submission) && s.submission ? "ontologies/#{s.submission.ontology.id.split('/')[-1]}" : ""}, Goo.vocabulary["Ontology"])

      def index_id
        self.bring(:ontology) if self.bring?(:ontology)
        return nil unless self.ontology
        latest = self.ontology.latest_submission(status: :any)
        return nil unless latest
        "#{self.id.to_s}_#{self.ontology.acronym}_#{latest.submissionId}"
      end

      def index_doc
        return {} unless self.ontology
        latest = self.ontology.latest_submission(status: :any)
        return {} unless latest
        self.ontology.bring(:acronym) if self.ontology.bring?(:acronym)
        self.ontology.bring(:ontologyType) if self.ontology.bring?(:ontologyType)

        doc = {
          :resource_id => self.id.to_s,
          :prefLabel => self.label,
          :obsolete => false,
          :provisional => true,
          :ontologyId => latest.id.to_s,
          :submissionAcronym => self.ontology.acronym,
          :submissionId => latest.submissionId,
          :ontologyType => self.ontology.ontologyType.get_code_from_id
        }

        all_attrs = self.to_hash
        std = [:id, :synonym, :definition]

        std.each do |att|
          cur_val = all_attrs[att]
          # don't store empty values
          next if cur_val.nil? || cur_val.empty?

          if (cur_val.is_a?(Array))
            doc[att] = []
            cur_val = cur_val.uniq
            cur_val.map { |val| doc[att] << (val.kind_of?(Goo::Base::Resource) ? val.id.to_s : val.to_s.strip) }
          else
            doc[att] = cur_val.to_s.strip
          end
        end

        doc
      end

      def index
        if index_id
          unindex
          super
          LinkedData::Models::Ontology.indexCommit
        end
      end

      def unindex
        ind_id = index_id

        if ind_id
          query = "id:#{solr_escape(ind_id)}"
          LinkedData::Models::Ontology.unindexByQuery(query)
          LinkedData::Models::Ontology.indexCommit
        end
      end

      ##
      # Override save to allow indexing
      def save(*args)
        super(*args)
        index
        return self
      end

      def delete(*args)
        # remove index entries
        unindex
        super(*args)
      end

      def solr_escape(text)
        RSolr.solr_escape(text).gsub(/\s+/,"\\ ")
      end

      def self.children(source_uri)
        source_uri = RDF::URI.new(source_uri) unless source_uri.is_a?(RDF::URI)
        LinkedData::Models::ProvisionalClass.where(subclassOf: source_uri).include(LinkedData::Models::ProvisionalClass.attributes).all
      end

    end
  end
end
