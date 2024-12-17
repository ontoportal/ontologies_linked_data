module LinkedData
  module Concerns
    module Mappings
      module Count
        def mapping_counts(enable_debug = false, logger = nil, reload_cache = false, arr_acronyms = [])
          logger = nil unless enable_debug
          t = Time.now
          latest = self.retrieve_latest_submissions(options = { acronyms: arr_acronyms })
          counts = {}
          # Counting for External mappings
          t0 = Time.now
          external_uri = LinkedData::Models::ExternalClass.graph_uri
          exter_counts = mapping_ontologies_count(external_uri, nil, reload_cache = reload_cache)
          exter_total = 0
          exter_counts.each do |k, v|
            exter_total += v
          end
          counts[external_uri.to_s] = exter_total
          logger.info("Time for External Mappings took #{Time.now - t0} sec. records #{exter_total}") if enable_debug
          LinkedData.settings.interportal_hash ||= {}
          # Counting for Interportal mappings
          LinkedData.settings.interportal_hash.each_key do |acro|
            t0 = Time.now
            interportal_uri = LinkedData::Models::InterportalClass.graph_uri(acro)
            inter_counts = mapping_ontologies_count(interportal_uri, nil, reload_cache = reload_cache)
            inter_total = 0
            inter_counts.each do |k, v|
              inter_total += v
            end
            counts[interportal_uri.to_s] = inter_total
            if enable_debug
              logger.info("Time for #{interportal_uri.to_s} took #{Time.now - t0} sec. records #{inter_total}")
            end
          end
          # Counting for mappings between the ontologies hosted by the BioPortal appliance
          i = 0
          epr = Goo.sparql_query_client(:main)

          latest.each do |acro, sub|
            self.handle_triple_store_downtime(logger) if Goo.backend_4s?
            t0 = Time.now
            s_counts = self.mapping_ontologies_count(sub, nil, reload_cache = reload_cache)
            s_total = 0

            s_counts.each do |k, v|
              s_total += v
            end
            counts[acro] = s_total
            i += 1

            next unless enable_debug

            logger.info("#{i}/#{latest.count} " +
                          "Retrieved #{s_total} records for #{acro} in #{Time.now - t0} seconds.")
            logger.flush
          end

          if enable_debug
            logger.info("Total time #{Time.now - t} sec.")
            logger.flush
          end
          return counts
        end

        def create_mapping_counts(logger, arr_acronyms = [])
          ont_msg = arr_acronyms.empty? ? "all ontologies" : "ontologies [#{arr_acronyms.join(', ')}]"

          time = Benchmark.realtime do
            create_mapping_count_totals_for_ontologies(logger, arr_acronyms)
          end
          logger.info("Completed rebuilding total mapping counts for #{ont_msg} in #{(time / 60).round(1)} minutes.")
          puts "create mappings total count time: #{time}"

          time = Benchmark.realtime do
            create_mapping_count_pairs_for_ontologies(logger, arr_acronyms)
          end
          puts "create mappings pair count time: #{time}"
          logger.info("Completed rebuilding mapping count pairs for #{ont_msg} in #{(time / 60).round(1)} minutes.")
        end

        def create_mapping_count_totals_for_ontologies(logger, arr_acronyms)
          new_counts = mapping_counts(enable_debug = true, logger = logger, reload_cache = true, arr_acronyms)
          persistent_counts = {}
          f = Goo::Filter.new(:pair_count) == false

          LinkedData::Models::MappingCount.where.filter(f)
                                          .include(:ontologies, :count)
                                          .include(:all)
                                          .all
                                          .each do |m|
            persistent_counts[m.ontologies.first] = m
          end

          latest = self.retrieve_latest_submissions(options = { acronyms: arr_acronyms })
          delete_zombie_mapping_count(persistent_counts.values, latest.values.compact.map { |sub| sub.ontology.acronym })

          num_counts = new_counts.keys.length
          ctr = 0

          new_counts.each_key do |acr|
            new_count = new_counts[acr]
            ctr += 1

            if persistent_counts.include?(acr)
              inst = persistent_counts[acr]
              if new_count.zero?
                inst.delete if inst.persistent?
              elsif new_count != inst.count
                inst.bring_remaining
                inst.count = new_count

                begin
                  if inst.valid?
                    inst.save
                  else
                    logger.error("Error updating mapping count for #{acr}: #{inst.id.to_s}. #{inst.errors}")
                    next
                  end
                rescue Exception => e
                  logger.error("Exception updating mapping count for #{acr}: #{inst.id.to_s}. #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
                  next
                end
              end
            else
              m = LinkedData::Models::MappingCount.new
              m.ontologies = [acr]
              m.pair_count = false
              m.count = new_count

              begin
                if m.valid?
                  m.save
                else
                  logger.error("Error saving new mapping count for #{acr}. #{m.errors}")
                  next
                end
              rescue Exception => e
                logger.error("Exception saving new mapping count for #{acr}. #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
                next
              end
            end
            remaining = num_counts - ctr
            logger.info("Total mapping count saved for #{acr}: #{new_count}. " << ((remaining.positive?) ? "#{remaining} counts remaining..." : "All done!"))
          end
        end

        # This generates pair mapping counts for the given
        # ontologies to ALL other ontologies in the system
        def create_mapping_count_pairs_for_ontologies(logger, arr_acronyms)

          latest_submissions = self.retrieve_latest_submissions(options = { acronyms: arr_acronyms })
          all_latest_submissions = self.retrieve_latest_submissions
          ont_total = latest_submissions.length
          logger.info("There is a total of #{ont_total} ontologies to process...")
          ont_ctr = 0
          # filename = 'mapping_pairs.ttl'
          # temp_dir = Dir.tmpdir
          # temp_file_path = File.join(temp_dir, filename)
          # temp_dir = '/Users/mdorf/Downloads/test/'
          # temp_file_path = File.join(File.dirname(file_path), "test.ttl")
          # fsave = File.open(temp_file_path, "a")
          latest_submissions.each do |acr, sub|
            self.handle_triple_store_downtime(logger) if Goo.backend_4s?
            new_counts = nil

            time = Benchmark.realtime do
              new_counts = self.mapping_ontologies_count(sub, nil, reload_cache = true)
            end
            logger.info("Retrieved new mapping pair counts for #{acr} in #{time} seconds.")
            ont_ctr += 1
            persistent_counts = {}
            LinkedData::Models::MappingCount.where(pair_count: true).and(ontologies: acr)
                                            .include(:ontologies, :count).all.each do |m|
              other = m.ontologies.first
              other = m.ontologies.last if other == acr
              persistent_counts[other] = m
            end

            delete_zombie_mapping_count(persistent_counts.values, all_latest_submissions.values.compact.map { |s| s.ontology.acronym })

            num_counts = new_counts.keys.length
            logger.info("Ontology: #{acr}. #{num_counts} mapping pair counts to record...")
            logger.info("------------------------------------------------")
            ctr = 0

            new_counts.each_key do |other|
              new_count = new_counts[other]
              ctr += 1

              if persistent_counts.include?(other)
                inst = persistent_counts[other]
                if new_count.zero?
                  inst.delete
                elsif new_count != inst.count
                  inst.bring_remaining if inst.persistent?
                  inst.pair_count = true
                  inst.count = new_count

                  begin
                    if inst.valid?
                      inst.save()
                      # inst.save({ batch: fsave })
                    else
                      logger.error("Error updating mapping count for the pair [#{acr}, #{other}]: #{inst.id.to_s}. #{inst.errors}")
                      next
                    end
                  rescue Exception => e
                    logger.error("Exception updating mapping count for the pair [#{acr}, #{other}]: #{inst.id.to_s}. #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
                    next
                  end
                end
              else
                next unless new_counts.key?(other)

                m = LinkedData::Models::MappingCount.new
                m.count = new_count
                m.ontologies = [acr, other]
                m.pair_count = true
                begin
                  if m.valid?
                    m.save()
                    # m.save({ batch: fsave })
                  else
                    logger.error("Error saving new mapping count for the pair [#{acr}, #{other}]. #{m.errors}")
                    next
                  end
                rescue Exception => e
                  logger.error("Exception saving new mapping count for the pair [#{acr}, #{other}]. #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
                  next
                end
              end
              remaining = num_counts - ctr
              logger.info("Mapping count saved for the pair [#{acr}, #{other}]: #{new_count}. " << ((remaining.positive?) ? "#{remaining} counts remaining for #{acr}..." : "All done!"))
              wait_interval = 250

              next unless (ctr % wait_interval).zero?

              sec_to_wait = 1
              logger.info("Waiting #{sec_to_wait} second" << ((sec_to_wait > 1) ? 's' : '') << '...')
              sleep(sec_to_wait)
            end
            remaining_ont = ont_total - ont_ctr
            logger.info("Completed processing pair mapping counts for #{acr}. " << ((remaining_ont.positive?) ? "#{remaining_ont} ontologies remaining..." : "All ontologies processed!"))
          end
          # fsave.close
        end

        private

        def delete_zombie_mapping_count(existent_counts, submissions_ready)
          special_mappings = ["http://data.bioontology.org/metadata/ExternalMappings",
                              "http://data.bioontology.org/metadata/InterportalMappings/agroportal",
                              "http://data.bioontology.org/metadata/InterportalMappings/ncbo",
                              "http://data.bioontology.org/metadata/InterportalMappings/sifr"]

          existent_counts.each do |mapping|
            next if mapping.ontologies.size == 1 && !(mapping.ontologies & special_mappings).empty?
            next if mapping.ontologies.all? { |x| submissions_ready.include?(x) }
            next unless mapping.persistent?

            mapping.delete
          end
        end
      end
    end
  end
end
