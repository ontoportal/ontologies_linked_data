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


    agents =[
      LinkedData::Models::Agent.new(name:"name 0", agentType: 'organization',creator: @@user1 ),
      LinkedData::Models::Agent.new(name:"name 1", agentType: 'person', creator: @@user1 ),
      LinkedData::Models::Agent.new(name:"name 2", agentType: 'person', creator: @@user1 )
    ]

    affiliations = agents[0..2].map{ |a| a.save }
    agent = agents.last
    agent.affiliations = affiliations


    refute agent.valid?
    refute_nil agent.errors[:affiliations][:is_organization]

    affiliations.each{|x| x.delete}
  end

  def test_identifier_no_valid
    refute LinkedData::Models::AgentIdentifier.new(notation: 'https://ror.org/000h6jb29"', schemaAgency: 'ROR', creator: @@user1).valid?
    assert LinkedData::Models::AgentIdentifier.new(notation: '000h6jb29"', schemaAgency: 'ROR', creator: @@user1).valid?
  end

end
