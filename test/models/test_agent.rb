require_relative "../test_case"

class TestAgent < LinkedData::TestCase

  def self.before_suite
    self.new("before_suite").teardown
    @@user1 = LinkedData::Models::User.new(:username => "user11111", :email => "some1111@email.org" )
    @@user1.passwordHash = "some random pass hash"
    @@user1.save
  end

  def self.after_suite
    self.new("before_suite").teardown

    @@user1.delete
  end



  def test_agent_no_valid

    @agents =[
      LinkedData::Models::Agent.new(name:"name 0", email:"test_0@test.com", agentType: 'organization',creator: @@user1 ),
      LinkedData::Models::Agent.new(name:"name 1", email:"test_1@test.com", agentType: 'person', creator: @@user1 ),
      LinkedData::Models::Agent.new(name:"name 2", email:"test_2@test.com",  agentType: 'person', creator: @@user1 )
    ]
    @identifiers = [
      LinkedData::Models::AgentIdentifier.new(notation: '000h6jb29', schemaAgency: 'ROR', creator: @@user1),
      LinkedData::Models::AgentIdentifier.new(notation: '000h6jb29', schemaAgency: 'ORCID', creator: @@user1),
    ]

    @identifiers.each {|i| i.save}

    affiliations = @agents[0..2].map{ |a| a.save }
    agent = @agents.last
    agent.affiliations = affiliations


    refute agent.valid?
    refute_nil agent.errors[:affiliations][:is_organization]

    affiliations.each{|x| x.delete}


    agents = @agents[0..2].map do |a|
      a.identifiers = @identifiers
      a
    end

    assert agents.first.valid?
    agents.first.save

    second_agent = agents.last
    refute second_agent.valid?
    refute_nil second_agent.errors[:identifiers][:unique_identifiers]


    @identifiers.each{|i| i.delete}
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

end
