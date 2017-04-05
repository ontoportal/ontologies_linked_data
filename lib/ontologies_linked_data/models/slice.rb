require 'ontologies_linked_data/models/group'

module LinkedData::Models
  class Slice < LinkedData::Models::Base
    model :slice, name_with: :acronym
    attribute :acronym, enforce: [:unique, :existence, lambda {|inst,attr| validate_acronym(inst, attr)}]
    attribute :name, enforce: [:existence]
    attribute :description
    attribute :created, enforce: [:date_time], :default => lambda { |record| DateTime.now }
    attribute :ontologies, enforce: [:existence, :list, :ontology]

    cache_timeout 3600

    def self.validate_acronym(inst, attr)
      inst.bring(attr) if inst.bring?(attr)
      value = inst.send(attr)
      acronym_regex = /\A[-_a-z]+\Z/
      if (acronym_regex.match value).nil?
        return [:acronym_value_validator,"The acronym value #{value} is invalid"]
      end
      return [:acronym_value_validator, nil]
    end

    def ontology_id_set
      @ontology_set ||= Set.new(self.ontologies.map {|o| o.id.to_s})
    end
  end
end
