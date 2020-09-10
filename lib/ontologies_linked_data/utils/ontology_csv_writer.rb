require 'csv'
require 'zlib'

module LinkedData
  module Utils
    class OntologyCSVWriter

      # Column headers for Standard BioPortal properties.
      CLASS_ID = 'Class ID'
      PREF_LABEL = 'Preferred Label'
      SYNONYMS = 'Synonyms'
      DEFINITIONS = 'Definitions'
      CUI = 'CUI'
      SEMANTIC_TYPES = 'Semantic Types'
      OBSOLETE = 'Obsolete'
      PARENTS = 'Parents'

      def open(ont, path)
        @file = File.new(path, 'w')
        @gz = Zlib::GzipWriter.new(@file)
        @csv = CSV.new(@gz, headers: true, return_headers: true, write_headers: true)
        @property_ids = Hash[ont.properties.map { |prop| [prop.id.to_s, get_prop_label(prop)] }]
        write_header(ont)
      end

      def write_header(ont)
        props_bioportal_standard = [CLASS_ID,PREF_LABEL,SYNONYMS,DEFINITIONS,OBSOLETE,CUI,SEMANTIC_TYPES,PARENTS]
        props_other = ont.properties.map { |prop| get_prop_label(prop) }
        props_other.sort! { |a,b| a.downcase <=> b.downcase }
        @headers = props_bioportal_standard.concat(props_other)
        @csv << @headers
      end

      def write_class(ont_class)
        row = CSV::Row.new(@headers, Array.new(@headers.size), false)

        # ID
        row[CLASS_ID] = ont_class.id

        # Preferred label
        row[PREF_LABEL] = ont_class.prefLabel

        # Synonyms
        synonyms = ont_class.synonym
        row[SYNONYMS] = synonyms.join('|') unless synonyms.empty?

        # Definitions
        definitions = ont_class.definition
        row[DEFINITIONS] = definitions.join('|') unless definitions.empty?

        # Obsolete
        row[OBSOLETE] = ont_class.obsolete

        # CUI
        cuis = ont_class.cui
        row[CUI] = cuis.join('|') unless cuis.empty?

        # Semantic types
        semantic_types = ont_class.semanticType
        row[SEMANTIC_TYPES] = semantic_types.join('|') unless semantic_types.empty?

        # Parents
        parents = ont_class.parents
        row[PARENTS] = get_parent_ids(parents) unless parents.empty?

        # Other properties.
        props = ont_class.properties
        props.each do |p|
          id = p.first.to_s
          if @property_ids.has_key?(id)
            values = p.last.map { |v| v.to_s }
            row[@property_ids[id]] = values.join('|')
          end
        end

        @csv << row
      end

      def close
        @gz.close
        @file.close
        @csv.close
      end

      def get_parent_ids(parents)
        parent_ids = []
        parents.each do |parent|
          parent_ids << parent.id
        end
        return parent_ids.join('|')
      end

      def get_prop_label(prop)
        prop.label.empty? ? prop.id.to_s : prop.label.first.to_s
      end
    end
  end
end