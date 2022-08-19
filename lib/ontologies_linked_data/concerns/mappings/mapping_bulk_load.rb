module LinkedData
  module Concerns
    module Mappings
      module BulkLoad
        # A method to easily add a new mapping without using ontologies_api
        # Where the mapping hash contain classes, relation, creator and comment)

        def bulk_load_mappings(mappings_hash, user_creator, check_exist: true)
          mappings_hash&.map { |m| load_mapping(m, user_creator ,check_exist: check_exist) }
        end

        def load_mapping(mapping_hash, user_creator, check_exist: true)

          raise ArgumentError, 'Mapping hash does not contain classes' unless mapping_hash[:classes]
          raise ArgumentError, 'Mapping hash does not contain at least 2 terms' if mapping_hash[:classes].length > 2
          raise ArgumentError, 'Mapping hash does not contain mapping relation' unless mapping_hash[:process][:relation]

          if mapping_hash[:relation].is_a?(Array)
            if mapping_hash[:process][:relation].length > 5
              raise ArgumentError, 'Mapping hash contains too many mapping relations (max 5)'
            end

            mapping_hash[:relation].each do |relation|
              URI(relation)
            rescue URI::InvalidURIError
              raise ArgumentError, "#{relation} is not a valid URI for relations."
            end
          end
          raise ArgumentError, 'Mapping hash does not contain user creator ID' if user_creator.nil?

          mapping_process = mapping_hash[:process]
          subject_submission = find_submission_by_ontology_id(mapping_process[:subject_source_id])
          object_submission = find_submission_by_ontology_id(mapping_process[:object_source_id])

          subject_class, subject_submission = find_class(mapping_hash[:classes].first, subject_submission)
          object_class, object_submission = find_class(mapping_hash[:classes].last, object_submission)

          classes = [subject_class, object_class]

          process = create_mapping_process(mapping_process, subject_submission, object_submission, user_creator)
          if check_exist && LinkedData::Mappings.check_mapping_exist(classes, process.relation)
            raise ArgumentError, 'Mapping already exists'
          end
          process.save
          begin
            mapping = LinkedData::Mappings.create_rest_mapping(classes, process)
          rescue StandardError => e
            # Remove the created process if the following steps of the mapping fail
            process.delete
            raise IOError, "Loading mapping has failed. Message: #{e.message.to_s}"
          end

          mapping
        end

        private

        def create_mapping_process(mapping_process, subject_submission, object_submission, user)
          process = LinkedData::Models::MappingProcess.new
          relations_array = Array(mapping_process[:relation]).map { |r| RDF::URI.new(r) }
          process.relation = relations_array.first
          process.creator = user
          process.subject_source_id =  RDF::URI.new(subject_submission.uri) || mapping_process[:subject_source_id]
          process.object_source_id = RDF::URI.new(object_submission.uri) || mapping_process[:object_source_id]
          process.date = DateTime.parse(mapping_process[:date]) || DateTime.now
          process_fields = %i[source source_name comment name source_contact_info]
          process_fields.each do |att|
            process.send("#{att}=", mapping_process[att]) if mapping_process[att]
          end
          process
        end

        # Generate URNs for class mapping (urn:ONT_ACRO:CLASS_URI)
        def generate_class_urns(classes)
          class_urns = []
          classes.each do |c|
            if c.instance_of? LinkedData::Models::Class
              acronym = c.submission.id.to_s.split("/")[-3]
              class_urns << RDF::URI.new(LinkedData::Models::Class.urn_id(acronym, c.id.to_s))
            elsif c.is_a?(Hash)
              # Generate classes urns using the source (e.g.: ncbo or ext), the ontology acronym and the class id
              class_urns << RDF::URI.new("#{c[:source]}:#{c[:ontology]}:#{c[:id]}")
            else
              class_urns << RDF::URI.new(c.urn_id())
            end
          end
          class_urns
        end

        def find_submission_by_ontology_id(ontology_id)
          return nil if ontology_id.nil?

          o = LinkedData::Models::Ontology.where(submissions: { uri: ontology_id })
                                          .include(submissions: %i[submissionId submissionStatus uri])
                                          .first
          latest_submission = o.nil? ? nil : o.latest_submission
          raise ArgumentError, "Ontology with ID `#{ontology_id}` not found" if o.nil?

          latest_submission
        end

        def find_ontology_by_class(class_instance)
          class_instance.submission.bring :ontology
          class_instance.submission.ontology
        end

        def find_submission_by_class_id(class_id)
          params = {
            require_exact_match: true,
            defType: 'edismax',
            qf: 'resource_id'
          }
          query = class_id
          search_response = LinkedData::Models::Class.search(query, params)
          search_response = search_response['response']['docs']
          raise ArgumentError, "Class ID `#{class_id}` not found" if search_response.empty?

          search_response.each do |resp|
            submission_id = resp['ontologyId']
            class_instance = LinkedData::Models::OntologySubmission.find(RDF::URI.new(submission_id)).include(:uri).first
            return  class_instance unless class_instance.nil?
          end

        end

        def find_class(class_id, submission)
          submission = find_submission_by_class_id(class_id) if submission.nil?

          c = LinkedData::Models::Class.find(RDF::URI.new(class_id))
                                       .in(submission)
                                       .first
          raise ArgumentError, "Class ID `#{class_id}` not found in `#{submission.id}`" if c.nil?

          [c, submission]
        end

      end
    end
  end
end





