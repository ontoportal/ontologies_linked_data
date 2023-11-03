require_relative "../test_case"

class TestAgent < LinkedData::TestCase

  def self.before_suite
    backend_4s_delete
    self.new("before_suite").teardown
    @@user1 = LinkedData::Models::User.new(:username => "user11111", :email => "some1111@email.org")
    @@user1.passwordHash = "some random pass hash"
    @@user1.save
  end

  def self.after_suite
    self.new("before_suite").teardown

    @@user1.delete
  end

  def test_agent_no_valid

    @agents = [
      LinkedData::Models::Agent.new(name: "name 0", email: "test_0@test.com", agentType: 'organization', creator: @@user1),
      LinkedData::Models::Agent.new(name: "name 1", email: "test_1@test.com", agentType: 'person', creator: @@user1),
      LinkedData::Models::Agent.new(name: "name 2", email: "test_2@test.com", agentType: 'person', creator: @@user1)
    ]
    @identifiers = [
      LinkedData::Models::AgentIdentifier.new(notation: '000h6jb29', schemaAgency: 'ROR', creator: @@user1),
      LinkedData::Models::AgentIdentifier.new(notation: '000h6jb29', schemaAgency: 'ORCID', creator: @@user1),
    ]

    @identifiers.each { |i| i.save }

    affiliations = @agents[0..2].map { |a| a.save }
    agent = @agents.last
    agent.affiliations = affiliations

    refute agent.valid?
    refute_nil agent.errors[:affiliations][:is_organization]

    affiliations.each { |x| x.delete }

    agents = @agents[0..2].map do |a|
      a.identifiers = @identifiers
      a
    end

    assert agents.first.valid?
    agents.first.save

    second_agent = agents.last
    refute second_agent.valid?
    refute_nil second_agent.errors[:identifiers][:unique_identifiers]

    @identifiers.each { |i| i.delete }
  end

  def test_identifier_find
    id = LinkedData::Models::AgentIdentifier.new(notation: '000h6jb29', schemaAgency: 'ROR', creator: @@user1)
    id.save

    generated_id = LinkedData::Models::AgentIdentifier.generate_identifier('000h6jb29', 'ROR')
    id = LinkedData::Models::AgentIdentifier.find(generated_id).first

    refute_nil id

    id.delete
  end

  def test_identifier_no_valid
    refute LinkedData::Models::AgentIdentifier.new(notation: 'https://ror.org/000h6jb29', schemaAgency: 'ROR', creator: @@user1).valid?
    id = LinkedData::Models::AgentIdentifier.new(notation: '000h6jb29"', schemaAgency: 'ROR', creator: @@user1)

    assert id.valid?
    id.save

    refute LinkedData::Models::AgentIdentifier.new(notation: '000h6jb29"', schemaAgency: 'ROR', creator: @@user1).valid?

    assert LinkedData::Models::AgentIdentifier.new(notation: '000h6jb29"', schemaAgency: 'ORCID', creator: @@user1).valid?
    id.delete
  end

  def test_agent_usages
    count, acronyms, ontologies = create_ontologies_and_submissions(ont_count: 3, submission_count: 1,
                                                                    process_submission: false)

    o1 = ontologies[0]
    o2 = ontologies[1]
    o3 = ontologies[2]
    sub1 = o1.latest_submission(status: :any)
    sub2 = o2.latest_submission(status: :any)
    sub3 = o3.latest_submission(status: :any)
    refute_nil sub1
    refute_nil sub2
    refute_nil sub3

    agents = [LinkedData::Models::Agent.new(name: "name 0", email: "test_0@test.com", agentType: 'organization', creator: @@user1).save,
              LinkedData::Models::Agent.new(name: "name 1", email: "test_1@test.com", agentType: 'organization', creator: @@user1).save,
              LinkedData::Models::Agent.new(name: "name 2", email: "test_2@test.com", agentType: 'person', creator: @@user1).save]

    sub1.hasCreator = [agents.last]
    sub1.publisher = agents[0..1]
    sub1.fundedBy = [agents[0]]
    sub1.bring_remaining
    assert sub1.valid?
    sub1.save

    sub2.hasCreator = [agents.last]
    sub2.endorsedBy = [agents[0]]
    sub2.fundedBy = agents[0..1]
    sub2.bring_remaining
    assert sub2.valid?
    sub2.save

    usages = agents[0].usages

    assert_equal 2, usages.size

    refute_nil usages[sub1.id]
    assert_equal usages[sub1.id].map(&:to_s).sort, ["http://purl.org/dc/terms/publisher", "http://xmlns.com/foaf/0.1/fundedBy"].sort
    refute_nil usages[sub2.id].map(&:to_s).sort, ["http://omv.ontoware.org/2005/05/ontology#endorsedBy", "http://xmlns.com/foaf/0.1/fundedBy"].sort

    sub3.copyrightHolder = agents[0]
    sub3.bring_remaining
    sub3.save

    usages = agents[0].usages
    assert_equal 3, usages.size

    refute_nil usages[sub1.id]
    assert_equal usages[sub1.id].map(&:to_s).sort, ["http://purl.org/dc/terms/publisher", "http://xmlns.com/foaf/0.1/fundedBy"].sort
    assert_equal usages[sub2.id].map(&:to_s).sort, ["http://omv.ontoware.org/2005/05/ontology#endorsedBy", "http://xmlns.com/foaf/0.1/fundedBy"].sort
    assert_equal usages[sub3.id].map(&:to_s), ["http://schema.org/copyrightHolder"]

    agents.each{|x| x.delete}
  end
end
