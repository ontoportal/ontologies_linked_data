require 'parallel'
module LinkedData
  module Services
    class OntologySubmissionAllDataIndexer < OntologySubmissionProcess

      def process(logger, options = nil)
        status = LinkedData::Models::SubmissionStatus.find('INDEXED_ALL_DATA').first
        begin
          index_all_data(logger, options)
          @submission.add_submission_status(status)
        rescue StandardError
          @submission.add_submission_status(status.get_error_status)
        ensure
          @submission.save
        end
      end

      private

      def index_sorted_ids(ids, ontology, conn, logger, commit = true)
        total_triples = Parallel.map(ids.each_slice(1000), in_threads: 10) do |ids_slice|
          index_ids = 0
          triples_count = 0
          documents = {}
          time = Benchmark.realtime do
            documents, triples_count = fetch_triples(ids_slice, ontology)
          end

          return if documents.empty?

          logger.info("Worker #{Parallel.worker_number} > Fetched #{triples_count} triples of #{@submission.id} in #{time} sec.") if triples_count.positive?

          time = Benchmark.realtime do
            conn.index_document(documents.values, commit: false)
            conn.index_commit if commit
            index_ids = documents.size
            documents = {}
          end
          logger.info("Worker #{Parallel.worker_number} > Indexed #{index_ids} ids of #{@submission.id} in #{time} sec.")
          triples_count
        end
        total_triples.sum
      end

      def index_all_data(logger, commit: true)
        page = 1
        size = 10_000
        count_ids = 0
        total_time = 0
        total_triples = 0
        old_count = -1

        ontology = @submission.bring(:ontology).ontology
                              .bring(:acronym).acronym
        conn = init_search_collection(ontology)

        ids = {}

        while count_ids != old_count
          old_count = count_ids
          count = 0
          time = Benchmark.realtime do
            ids = fetch_sorted_ids(size, page)
            count = ids.size
          end

          count_ids += count
          total_time += time
          page += 1

          next unless count.positive?

          logger.info("Fetched #{count} ids of #{@submission.id} page: #{page} in #{time} sec.")

          time = Benchmark.realtime do
            total_triples += index_sorted_ids(ids, ontology, conn, logger, commit)
          end
          logger.info("Indexed #{total_triples} triples of #{@submission.id} page: #{page} in #{time} sec.")

          total_time += time
        end
        logger.info("Completed indexing all ontology data: #{@submission.id} in #{total_time} sec. (#{count_ids} ids / #{total_triples} triples)")
        logger.flush
      end

      def fetch_sorted_ids(size, page)
        query = Goo.sparql_query_client.select(:id)
                   .distinct
                   .from(RDF::URI.new(@submission.id))
                   .where(%i[id p v])
                   .limit(size)
                   .offset((page - 1) * size)

        query.each_solution.map(&:id).sort
      end

      def update_doc(doc, property, new_val)
        unescaped_prop = property.gsub('___', '://')

        unescaped_prop = unescaped_prop.gsub('_', '/')
        existent_val = doc["#{unescaped_prop}_t"] || doc["#{unescaped_prop}_txt"]

        if !existent_val && !property['#']
          unescaped_prop = unescaped_prop.sub(%r{/([^/]+)$}, '#\1') # change latest '/' with '#'
          existent_val = doc["#{unescaped_prop}_t"] || doc["#{unescaped_prop}_txt"]
        end

        if existent_val && new_val || new_val.is_a?(Array)
          doc.delete("#{unescaped_prop}_t")
          doc["#{unescaped_prop}_txt"] = Array(existent_val) + Array(new_val).map(&:to_s)
        elsif existent_val.nil? && new_val
          doc["#{unescaped_prop}_t"] = new_val.to_s
        end
        doc
      end

      def init_search_collection(ontology)
        @submission.class.clear_indexed_content(ontology)
      end

      def fetch_triples(ids_slice, ontology)
        documents = {}
        count = 0
        filter = ids_slice.map { |x| "?id = <#{x}>" }.join(' || ')
        query = Goo.sparql_query_client.select(:id, :p, :v)
                   .from(RDF::URI.new(@submission.id))
                   .where(%i[id p v])
                   .filter(filter)
        query.each_solution do |sol|
          count += 1
          doc = documents[sol[:id].to_s]
          doc ||= {
            id: "#{sol[:id]}_#{ontology}", submission_id_t: @submission.id.to_s,
            ontology_t: ontology, resource_model: @submission.class.model_name,
            resource_id: sol[:id].to_s
          }
          property = sol[:p].to_s
          value = sol[:v]

          if property.to_s.eql?(RDF.type.to_s)
            update_doc(doc, 'type', value)
          else
            update_doc(doc, property, value)
          end
          documents[sol[:id].to_s] = doc
        end
        [documents, count]
      end

    end
  end
end


