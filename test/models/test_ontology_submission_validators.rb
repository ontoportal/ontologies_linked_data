require_relative "./test_ontology_common"
require "logger"
require "rack"

class TestOntologySubmissionValidators < LinkedData::TestOntologyCommon

  def test_enforce_symmetric_ontologies
    ont_count, ont_acronyms, ontologies =
      create_ontologies_and_submissions(ont_count: 3, submission_count: 1,
                                        process_submission: false, acronym: 'NCBO-545')


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

  def test_status_align_callbacks
    ont_count, ont_acronyms, ontologies =
      create_ontologies_and_submissions(ont_count: 1, submission_count: 3,
                                        process_submission: false, acronym: 'NCBO-545')




    # Sanity check.
    assert_equal 1, ontologies.count
    ont = ontologies.first
    ont.bring :submissions
    ont.submissions.each { |s| s.bring(:submissionId) }
    assert_equal 3, ont.submissions.count

    # Sort submissions in descending order.
    sorted_submissions = ont.submissions.sort { |a,b| b.submissionId <=> a.submissionId }

    latest = sorted_submissions.first

    latest.bring :status, :deprecated

    assert_equal 'alpha', latest.status
    assert_equal false, latest.deprecated

    latest.status = 'retired'
    latest.bring_remaining
    latest.save

    sorted_submissions.each do |s|
      s.bring :status, :deprecated
      assert_equal 'retired', latest.status
      assert_equal true, latest.deprecated
    end
  end
end
