require_relative "../../test_case"

class TestUser < LinkedData::TestCase

  def self.before_suite
    self.new("before_suite").teardown
  end

  def self.after_suite
    self.new("after_suite").teardown
  end

  def setup
    @u = LinkedData::Models::User.new({
        username: "test_user",
        email: "test@example.com",
        password: "a_password"
      })
    assert @u.valid?
  end

  def teardown
    ["test_user1", "test_user", "test_user_datetime", "test_user_uuid"].each do |username|
      u = LinkedData::Models::User.where(username: username).first
      u.delete unless u.nil?
    end
  end

  def test_valid_user
    u = LinkedData::Models::User.new
    assert (not u.valid?)

    u.username = "test_user1"
    u.email = "test@example.com"
    u.password = "a_password"
    assert u.valid?
  end

  def test_user_lifecycle
    assert_equal false, @u.exist?(reload=true)
    assert @u.valid?
    @u.save
    assert_equal true, @u.exist?(reload=true)
    @u.delete
    assert_equal false, @u.exist?(reload=true)
  end

  def test_user_role_assign
    u = @u
    u.role = [ LinkedData::Models::Users::Role.find("ADMINISTRATOR").include(:role).first ]

    assert u.valid?
    u.save
    assert u.role.length == 1

    assert_equal u.role.first.role, "ADMINISTRATOR"
    u.delete
  end

  def test_user_default_datetime
    u = LinkedData::Models::User.new({
        username: "test_user_datetime",
        email: "test@example.com",
        password: "a_password"
      })
    assert u.created.nil?
    assert u.valid?
    u.save
    assert u.created.instance_of?(DateTime)
    u.delete
  end

  def test_user_default_uuid
    u = LinkedData::Models::User.new({
        username: "test_user_uuid",
        email: "test@example.com",
        password: "a_password"
      })
    assert u.apikey.nil?
    assert u.valid?
    u.save
    assert u.apikey.instance_of?(String)
    u.delete
  end

  def test_user_subscription_load
    to_load = LinkedData::Models::User.goo_attrs_to_load([:subscription])
    assert_equal [{ subscription: [:ontology, { notification_type: [:type] }], role: [:role] }], to_load
  end

end
