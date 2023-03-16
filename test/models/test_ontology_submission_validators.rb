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

  # Regroup all validity test related to a submission retired status (deprecated, valid date)
  def test_submission_retired_validity
    sorted_submissions = sorted_submissions_init

    latest = sorted_submissions.first

    latest.bring :status, :deprecated

    # Test default values
    assert_equal 'production', latest.status
    assert_equal false, latest.deprecated

    # Test deprecate_previous_submissions callback
    sorted_submissions[1..].each do |s|
      s.bring :deprecated, :valid
      assert_equal true, s.deprecated
      assert s.valid
    end

    latest.bring_remaining
    latest.status = 'retired'

    refute latest.valid?

    # Test retired status related attributes validators
    assert latest.errors[:deprecated][:deprecated_retired_align]
    assert latest.errors[:valid][:validity_date_retired_align]

    latest.deprecated = true
    latest.valid = DateTime.now

    assert latest.valid?
    latest.save

    # Test retired_previous_align callback
    sorted_submissions.each do |s|
      s.bring :status, :deprecated, :valid
      assert_equal 'retired', s.status
      assert_equal true, s.deprecated
      assert s.valid
    end

  end

  def test_modification_date_previous_align
    sorted_submissions = sorted_submissions_init

    latest = sorted_submissions[0]
    previous = sorted_submissions[1]

    latest.bring_remaining
    assert latest.valid?

    previous.bring_remaining
    previous.modificationDate = Date.today.to_datetime

    assert previous.valid?
    previous.save

    previous.bring_remaining
    assert Date.today.to_datetime, previous.modificationDate

    refute latest.valid?
    assert latest.errors[:modificationDate][:modification_date_previous_align]

    latest.modificationDate = Date.today.prev_day.to_datetime

    refute latest.valid?
    assert latest.errors[:modificationDate][:modification_date_previous_align]

    latest.modificationDate = (Date.today + 1).to_datetime

    assert latest.valid?
    latest.save
  end

  def test_has_prior_version_callback
    sorted_submissions = sorted_submissions_init

    sorted_submissions.each_cons(2) do |current, previous|
      current.bring :hasPriorVersion
      assert previous.id, current.hasPriorVersion
    end

  end

  private

  def sorted_submissions_init
    ont_count, ont_acronyms, ontologies =
      create_ontologies_and_submissions(ont_count: 1, submission_count: 3,
                                        process_submission: false, acronym: 'NCBO-545')

    assert_equal 1, ontologies.count
    ont = ontologies.first
    ont.bring :submissions
    ont.submissions.each { |s| s.bring(:submissionId) }
    assert_equal 3, ont.submissions.count

    ont.submissions.sort { |a, b| b.submissionId <=> a.submissionId }
  end

end
