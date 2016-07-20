require_relative "../test_case"

class TestProvisionalRelation < LinkedData::TestCase

  def setup
    _delete

    @user = LinkedData::Models::User.new({username: "Test User", email: "tester@example.org", password: "password"})
    assert @user.valid?, "Invalid User object #{@user.errors}"
    @user.save

    ont_count, ont_names, ont_models = create_ontologies_and_submissions(ont_count: 1, submission_count: 1, process_submission: true)
    @ontology = ont_models.first
    @ontology.bring(:name)
    @ontology.bring(:acronym)
    @submission = @ontology.bring(:submissions).submissions.first

    @provisional_class = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Class", creator: @user, ontology: @ontology})
    assert @provisional_class.valid?, "Invalid ProvisionalClass object #{@provisional_class.errors}"
    @provisional_class.save

    @relation_type = RDF::IRI.new "http://www.w3.org/2004/02/skos/core#exactMatch"

    @target_class_uri1 = RDF::IRI.new "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Image_Algorithm"
    @target_class_uri2 = RDF::IRI.new "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#Integration_and_Interoperability_Tools"

    @provisional_rel1 = LinkedData::Models::ProvisionalRelation.new({creator: @user, source: @provisional_class, relationType: @relation_type, targetClassId: @target_class_uri1, targetClassOntology: @ontology})
    assert @provisional_rel1.valid?, "Invalid ProvisionalRelation object #{@provisional_rel1.errors}"
    @provisional_rel1.save
    @provisional_rel2 = LinkedData::Models::ProvisionalRelation.new({creator: @user, source: @provisional_class, relationType: @relation_type, targetClassId: @target_class_uri2, targetClassOntology: @ontology})
    assert @provisional_rel2.valid?, "Invalid ProvisionalRelation object #{@provisional_rel2.errors}"
    @provisional_rel2.save
  end

  def _delete
    delete_ontologies_and_submissions
    user = LinkedData::Models::User.find("Test User").first
    user.delete unless user.nil?
  end

  def test_create_provisional_relation
    rel1 = LinkedData::Models::ProvisionalRelation.find(@provisional_rel1.id).first
    rel1.bring_remaining
    assert rel1.valid?

    rel2 = LinkedData::Models::ProvisionalRelation.find(@provisional_rel2.id).first
    rel2.bring_remaining
    assert rel2.valid?

    pc = LinkedData::Models::ProvisionalClass.find(@provisional_class.id).first
    pc.bring(:relations)

    assert_equal 2, pc.relations.length

    rel_ids = pc.relations.map{|rel| rel.id}
    assert_includes rel_ids, rel1.id
    assert_includes rel_ids, rel2.id
  end

  def test_find_unique_provisional_relation
    rel = LinkedData::Models::ProvisionalRelation.find_unique(@provisional_class.id, @relation_type, @target_class_uri1, @ontology.id)
    assert_equal @provisional_rel1.id, rel.id
  end

  def test_equals
    rel = LinkedData::Models::ProvisionalRelation.find_unique(@provisional_class.id, @relation_type, @target_class_uri1, @ontology.id)
    assert @provisional_rel1 == rel
  end

  def test_target_class
    target_class = @provisional_rel1.target_class
    assert_equal @target_class_uri1, target_class.id
    target_class.bring(:submission) if target_class.bring?(:submission)
    target_class.submission.bring(ontology: [:acronym]) if target_class.submission.bring?(:ontology)
    assert_equal @ontology.acronym, target_class.submission.ontology.acronym
  end

  def teardown
    super
    @provisional_class.delete
    @provisional_rel1.delete
    @provisional_rel2.delete
    rel1 = LinkedData::Models::ProvisionalRelation.find(@provisional_rel1.id).first
    assert_nil rel1
    rel2 = LinkedData::Models::ProvisionalRelation.find(@provisional_rel2.id).first
    assert_nil rel2
  end

end