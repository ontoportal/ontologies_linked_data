module LinkedData
  module Concerns
    module OntologySubmission
      module MetadataExtractor

        def extract_metadata(logger, user_params)

          version_info = extract_version
          ontology_iri = extract_ontology_iri

          self.version = version_info if version_info
          self.uri = ontology_iri if ontology_iri

          begin
            # Extract metadata directly from the ontology
            extract_ontology_metadata(logger, user_params)
            logger.info('Additional metadata extracted.')
          rescue StandardError => e
            e.backtrace
            logger.error("Error while extracting additional metadata: #{e}")
          end

          begin
            # Set default metadata
            set_default_metadata
            logger.info('Default metadata set.')
          rescue StandardError => e
            logger.error("Error while setting default metadata: #{e}")
          end

          self.save
        end

        def extract_version

          query = Goo.sparql_query_client.select(:versionInfo).distinct
                     .from(id)
                     .where([RDF::URI.new('http://bioportal.bioontology.org/ontologies/versionSubject'),
                             RDF::URI.new('http://www.w3.org/2002/07/owl#versionInfo'),
                             :versionInfo])

          sol = query.each_solution.first || {}
          sol[:versionInfo]&.to_s
        end

        def extract_ontology_iri
          query = Goo.sparql_query_client.select(:uri).distinct
                     .from(id)
                     .where([:uri,
                             RDF::URI.new('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'),
                             RDF::URI.new('http://www.w3.org/2002/07/owl#Ontology')])
          sol = query.each_solution.first || {}
          sol[:uri]&.to_s
        end

        private

        # Extract additional metadata about the ontology
        # First it extracts the main metadata, then the mapped metadata
        def extract_ontology_metadata(logger, user_params)
          user_params = {} if user_params.nil? || !user_params
          ontology_uri = uri
          logger.info("Extraction metadata from ontology #{ontology_uri}")

          # go through all OntologySubmission attributes. Returns symbols
          LinkedData::Models::OntologySubmission.attributes(:all).each do |attr|
            # for attribute with the :extractedMetadata setting on, and that have not been defined by the user
            attr_settings = LinkedData::Models::OntologySubmission.attribute_settings(attr)

            attr_not_excluded = user_params && !(user_params.key?(attr) && !user_params[attr].nil? && !user_params[attr].empty?)

            next unless attr_settings[:extractedMetadata] && attr_not_excluded

            # a boolean to check if a value that should be single have already been extracted
            single_extracted = false
            type = enforce?(attr, :list) ? :list : :string
            old_value = value(attr, type)

            unless attr_settings[:namespace].nil?
              property_to_extract = "#{attr_settings[:namespace].to_s}:#{attr.to_s}"
              hash_results = extract_each_metadata(ontology_uri, attr, property_to_extract, logger)
              single_extracted = send_value(attr, hash_results) unless hash_results.empty?
            end

            # extracts attribute value from metadata mappings
            attr_settings[:metadataMappings] ||= []

            attr_settings[:metadataMappings].each do |mapping|
              break if single_extracted

              hash_mapping_results = extract_each_metadata(ontology_uri, attr, mapping.to_s, logger)
              single_extracted = send_value(attr, hash_mapping_results) unless hash_mapping_results.empty?
            end

            new_value = value(attr, type)
            send_value(attr, old_value) if empty_value?(new_value) && !empty_value?(old_value)

          end
        end

        # Set some metadata to default values if nothing extracted
        def set_default_metadata

          self.identifier = uri.to_s if identifier.nil?

          self.deprecated = status.eql?('retired') if deprecated.nil?

          # Add the ontology hasDomain to the submission hasDomain metadata value
          ontology_domain_list = []
          ontology.bring(:hasDomain).hasDomain.each do |domain|
            ontology_domain_list << domain.id
          end

          self.hasDomain = '' if !ontology_domain_list.empty? && hasDomain.nil?

          self.hasDomain << ontology_domain_list.join(', ') unless hasDomain.nil?

          # Only get the first view because the attribute is not a list
          ontology_view = ontology.bring(:views).views.first
          self.hasPart = ontology_view.id if hasPart.nil? && !ontology_view.nil?

          # If no example identifier extracted: take the first class
          self.exampleIdentifier = LinkedData::Models::Class.in(self).first.id if exampleIdentifier.nil?

          # Metadata specific to BioPortal that have been removed:
          #if self.hostedBy.nil?
          #  self.hostedBy = [ RDF::URI.new("http://#{LinkedData.settings.ui_host}") ]
          #end

          # Add the search endpoint URL
          if openSearchDescription.nil?
            self.openSearchDescription = RDF::URI.new("#{LinkedData.settings.rest_url_prefix}search?ontologies=#{ontology.acronym}&q=")
          end

          # Search allow to search by URI too
          if uriLookupEndpoint.nil?
            self.uriLookupEndpoint = RDF::URI.new("#{LinkedData.settings.rest_url_prefix}search?ontologies=#{ontology.acronym}&require_exact_match=true&q=")
          end

          # Add the dataDump URL
          if dataDump.nil?
            self.dataDump = RDF::URI.new("#{LinkedData.settings.rest_url_prefix}ontologies/#{ontology.acronym}/download?download_format=rdf")
          end

          if csvDump.nil?
            self.csvDump = RDF::URI.new("#{LinkedData.settings.rest_url_prefix}ontologies/#{ontology.acronym}/download?download_format=csv")
          end

          # Add the previous submission as a prior version
          if submissionId > 1
=begin
          if prior_versions.nil?
            prior_versions = []
          else
            prior_versions = self.hasPriorVersion.dup
          end
          prior_versions.push(RDF::URI.new("#{LinkedData.settings.rest_url_prefix}ontologies/#{self.ontology.acronym}/submissions/#{self.submissionId - 1}"))
          self.hasPriorVersion = prior_versions
=end
            self.hasPriorVersion = RDF::URI.new("#{LinkedData.settings.rest_url_prefix}ontologies/#{ontology.acronym}/submissions/#{submissionId - 1}")
          end

          if hasOntologyLanguage.umls?
            self.hasOntologySyntax = 'http://www.w3.org/ns/formats/Turtle'
          elsif hasOntologyLanguage.obo?
            self.hasOntologySyntax = 'http://purl.obolibrary.org/obo/oboformat/spec.html'
          end

          # Define default properties for prefLabel, synonyms, definition, author:
          if hasOntologyLanguage.owl?
            self.prefLabelProperty = Goo.vocabulary(:skos)[:prefLabel] if prefLabelProperty.nil?
            self.synonymProperty = Goo.vocabulary(:skos)[:altLabel] if synonymProperty.nil?
            self.definitionProperty = Goo.vocabulary(:rdfs)[:comment] if definitionProperty.nil?
            self.authorProperty = Goo.vocabulary(:dc)[:creator] if authorProperty.nil?
            # Add also hierarchyProperty? Could not find any use of it
          end

          # Add the sparql endpoint URL
          if endpoint.nil? && LinkedData.settings.sparql_endpoint_url
            self.endpoint = RDF::URI.new(LinkedData.settings.sparql_endpoint_url)
          end

        end

        def empty_value?(value)
          value.nil? || (value.is_a?(Array) && value.empty?) || value.to_s.strip.empty?
        end

        def value(attr, type)
          val = send(attr.to_s)
          type.eql?(:list) ? Array(val) || [] : val || ''
        end

        def send_value(attr, value)

          if enforce?(attr, :list)
            # Add the retrieved value(s) to the attribute if the attribute take a list of objects
            metadata_values = value(attr, :list)
            metadata_values = metadata_values.dup

            metadata_values.push(*value.values)

            send("#{attr}=", metadata_values.uniq)
          elsif enforce?(attr, :concatenate)
            # if multiple value for this attribute, then we concatenate it
            # Add the concat at the very end, to easily join the content of the array
            metadata_values = value(attr, :string)
            metadata_values = metadata_values.split(', ')
            new_values = value.values.map { |x| x.to_s.split(', ') }.flatten
            send("#{attr}=", (metadata_values + new_values).uniq.join(', '))
          else
            # If multiple value for a metadata that should have a single value: taking one value randomly (the first in the hash)
            send("#{attr}=", value.values.first)
            return true
          end
          false
        end

        # Return a hash with the best literal value for an URI
        # it selects the literal according to their language: no language > english > french > other languages
        def select_metadata_literal(metadata_uri, metadata_literal, hash)
          return unless metadata_literal.is_a?(RDF::Literal)

          if hash.key?(metadata_uri)
            if metadata_literal.has_language?
              if !hash[metadata_uri].has_language?
                return hash
              else
                case metadata_literal.language
                when :en, :eng
                  # Take the value with english language over other languages
                  hash[metadata_uri] = metadata_literal
                  return hash
                when :fr, :fre
                  # If no english, take french
                  if hash[metadata_uri].language == :en || hash[metadata_uri].language == :eng
                    return hash
                  else
                    hash[metadata_uri] = metadata_literal
                    return hash
                  end
                else
                  return hash
                end
              end
            else
              # Take the value with no language in priority (considered as a default)
              hash[metadata_uri] = metadata_literal
              return hash
            end
          else
            hash[metadata_uri] = metadata_literal
            hash
          end
        end

        # A function to extract additional metadata
        # Take the literal data if the property is pointing to a literal
        # If pointing to an URI: first it takes the "omv:name" of the object pointed by the property, if nil it takes the "rdfs:label".
        # If not found it check for "omv:firstName + omv:lastName" (for "omv:Person") of this object. And to finish it takes the "URI"
        # The hash_results contains the metadataUri (objet pointed on by the metadata property) with the value we are using from it
        def extract_each_metadata(ontology_uri, attr, prop_to_extract, logger)

          query_metadata = <<eos

SELECT DISTINCT ?extractedObject ?omvname ?omvfirstname ?omvlastname ?rdfslabel
FROM #{id.to_ntriples}
WHERE {
  <#{ontology_uri}> #{prop_to_extract} ?extractedObject .
  OPTIONAL { ?extractedObject omv:name ?omvname } .
  OPTIONAL { ?extractedObject omv:firstName ?omvfirstname } .
  OPTIONAL { ?extractedObject omv:lastName ?omvlastname } .
  OPTIONAL { ?extractedObject rdfs:label ?rdfslabel } .
}
eos
          Goo.namespaces.each do |prefix, uri|
            query_metadata = "PREFIX #{prefix}: <#{uri}>\n" + query_metadata
          end

          #logger.info(query_metadata)
          # This hash will contain the "literal" metadata for each object (uri or literal) pointed by the metadata predicate
          hash_results = {}
          Goo.sparql_query_client.query(query_metadata).each_solution do |sol|
            value = sol[:extractedObject]
            if enforce?(attr, :uri)
              # If the attr is enforced as URI then it directly takes the URI
              hash_results[value] = value if value.is_a?(RDF::URI)
            elsif enforce?(attr, :date_time)
              begin
                hash_results[value] = DateTime.iso8601(value.to_s)
              rescue StandardError => e
                logger.error("Impossible to extract DateTime metadata for #{attr}: #{value}. It should follow iso8601 standards. Error message: #{e}")
              end
            elsif enforce?(attr, :integer)
              begin
                hash_results[value] = value.to_s.to_i
              rescue StandardError => e
                logger.error("Impossible to extract integer metadata for #{attr}: #{value}. Error message: #{e}")
              end
            elsif enforce?(attr, :boolean)
              case value.to_s.downcase
              when 'true'
                hash_results[value] = true
              when 'false'
                hash_results[value] = false
              else
                logger.error("Impossible to extract boolean metadata for #{attr}: #{value}. Error message: #{e}")
              end
            elsif value.is_a?(RDF::URI)
              hash_results = find_object_label(hash_results, sol, value)
            else
              # If this is directly a literal
              hash_results = select_metadata_literal(value, value, hash_results)
            end
          end
          hash_results
        end

        def find_object_label(hash_results, sol, value)
          if !sol[:omvname].nil?
            hash_results = select_metadata_literal(value, sol[:omvname], hash_results)
          elsif !sol[:rdfslabel].nil?
            hash_results = select_metadata_literal(value, sol[:rdfslabel], hash_results)
          elsif !sol[:omvfirstname].nil?
            hash_results = select_metadata_literal(value, sol[:omvfirstname], hash_results)
            # if first and last name are defined (for omv:Person)
            hash_results[value] = "#{hash_results[value]} #{sol[:omvlastname]}" unless sol[:omvlastname].nil?
          elsif !sol[:omvlastname].nil?
            # if only last name is defined
            hash_results = select_metadata_literal(value, sol[:omvlastname], hash_results)
          else
            # if the object is an URI but we are requesting a String
            hash_results[value] = value.to_s
          end
          hash_results
        end

        def enforce?(attr, type)
          LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(type)
        end

      end
    end
  end
end

