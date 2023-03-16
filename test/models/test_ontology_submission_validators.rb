require_relative "./test_ontology_common"
require "logger"
require "rack"

class TestOntologySubmissionValidators < LinkedData::TestOntologyCommon

  def test_enforce_symmetric_ontologies
    ontologies = []
    3.times do |i|
      submission_parse("TEST-ONT-#{i}",
                       "TEST ONT  #{i}",
                       './test/data/ontology_files/fake_for_mappings.owl', i,
                       process_rdf: true, index_search: false,
                       run_metrics: false, reasoning: false)
    end

    3.times do |i|
      ont = LinkedData::Models::Ontology.where(acronym: "TEST-ONT-#{i}").first
      next unless ont

      ontologies << ont
    end

    assert_equal 3, ontologies.size

    ontologies[0].bring :submissions
    first_sub = ontologies[0].submissions.last

    refute_nil first_sub
    first_sub.bring :ontologyRelatedTo

    assert_empty first_sub.ontologyRelatedTo
    first_sub.ontologyRelatedTo = [ontologies[1].id, ontologies[2].id]
    first_sub.bring_remaining


    assert first_sub.valid?

    first_sub.save
    sub = nil
    2.times do |i|
      ontologies[i + 1].bring :submissions
      sub = ontologies[i + 1].submissions.last
      sub.bring :ontologyRelatedTo
      assert_equal [ontologies[0].id], sub.ontologyRelatedTo
    end

    #sub is the submission of the ontology 2
    sub.bring_remaining
    sub.ontologyRelatedTo = []
    sub.save

    first_sub.bring :ontologyRelatedTo
    assert_equal [ontologies[1].id], first_sub.ontologyRelatedTo

  end
end
