require_relative "./test_ontology_common"
require "logger"
require "rack"

class TestOntologySubmissionValidators < LinkedData::TestOntologyCommon

  def test_enforce_symmetric_ontologies
    skip('skip new callbacks tests until reimplemented')
    ontologies_properties_callbacks(:ontologyRelatedTo)
  end

  def test_lexvo_language_validator

    submissions = sorted_submissions_init(1)

    sub = submissions.first

    sub.bring_remaining
    assert sub.valid?

    sub.naturalLanguage = ["fr" , "http://iso639-3/eng"]

    refute sub.valid?
    assert sub.errors[:naturalLanguage][:lexvo_language]

    sub.naturalLanguage = [RDF::URI.new('http://lexvo.org/id/iso639-3/fra'),
                           RDF::URI.new('http://lexvo.org/id/iso639-3/eng')]

    assert sub.valid?
  end

  # Regroup all validity test related to a submission retired status (deprecated, valid date)
  def test_submission_retired_validity
    skip('skip new callbacks tests until reimplemented')
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

  def test_update_submissions_has_part
    skip('skip new callbacks tests until reimplemented')
    ont_count, ont_acronyms, ontologies =
      create_ontologies_and_submissions(ont_count: 3, submission_count: 1,
                                        process_submission: false, acronym: 'NCBO-545')

    assert_equal 3, ontologies.size

    ontologies.each { |o| o.bring(:viewOf) }
    ont_one = ontologies[0]
    ont_two = ontologies[1]
    ont_three = ontologies[2]

    ont_two.bring_remaining
    ont_three.bring_remaining

    ont_two.viewOf = ont_one
    ont_three.viewOf = ont_one

    ont_two.save
    ont_three.save

    ont_one.bring :submissions

    sub = ont_one.submissions.first

    refute_nil sub

    sub.bring :hasPart if sub.bring?(:hasPart)
    assert_equal [ont_two.id, ont_three.id].sort, sub.hasPart.sort

    sub.hasPart = [ont_two.id]

    refute sub.valid?
    assert sub.errors[:hasPart][:include_ontology_views]

    ont_two.viewOf = nil

    ont_two.save

    sub.bring :hasPart
    assert_equal [ont_three.id].sort, sub.hasPart.sort

    ont_three.viewOf = nil
    ont_three.save

    sub.bring_remaining
    sub.hasPart = []
    sub.save

  end

  def test_inverse_use_imports_callback
    ontologies_properties_callbacks(:useImports, :usedBy)
  end

  private

  def sorted_submissions_init(submission_count = 3)
    ont_count, ont_acronyms, ontologies =
      create_ontologies_and_submissions(ont_count: 1, submission_count: submission_count,
                                        process_submission: false, acronym: 'NCBO-545')

    assert_equal 1, ontologies.count
    ont = ontologies.first
    ont.bring :submissions
    ont.submissions.each { |s| s.bring(:submissionId) }
    assert_equal submission_count, ont.submissions.count

    ont.submissions.sort { |a, b| b.submissionId <=> a.submissionId }
  end


  def ontologies_properties_callbacks(attr, inverse_attr = nil)
    skip('skip new callbacks tests until reimplemented')
    inverse_attr = attr unless  inverse_attr
    ont_count, ont_acronyms, ontologies =
      create_ontologies_and_submissions(ont_count: 3, submission_count: 1,
                                        process_submission: false, acronym: 'NCBO-545')


    assert_equal 3, ontologies.size

    ontologies[0].bring :submissions
    first_sub = ontologies[0].submissions.last

    refute_nil first_sub
    first_sub.bring attr

    assert_empty first_sub.send(attr)
    first_sub.bring_remaining
    first_sub.send( "#{attr}=",[ontologies[1].id, ontologies[2].id])

    assert first_sub.valid?

    first_sub.save

    sub = nil
    2.times do |i|
      ontologies[i + 1].bring :submissions
      sub = ontologies[i + 1].submissions.last
      sub.bring(inverse_attr)
      assert_equal [ontologies[0].id], sub.send(inverse_attr)
    end

    #sub is the submission of the ontology 2
    sub.bring_remaining
    sub.send("#{inverse_attr}=", [])
    sub.save

    first_sub.bring(attr)
    assert_equal [ontologies[1].id], first_sub.send(attr)
  end
end
