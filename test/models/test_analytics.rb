require_relative "../test_case"

class LinkedData::Models::User
  @@user_analytics = {}

  def self.update_class_variable(new_value)
    @@user_analytics = new_value
  end
  def self.load_data(field_name)
    @@user_analytics
  end
end

class LinkedData::Models::Ontology
  def self.load_analytics_data
    ontologies_analytics = {}
    acronyms = %w[E-PHY AGROVOC TEST]
    acronyms.each do |acronym|
      ontologies_analytics[acronym] = {
        "2021" => (1..12).map { |i| [i.to_s, i * 2021] }.to_h,
        "2022" => (1..12).map { |i| [i.to_s, i * 2022] }.to_h,
        "2023" => (1..12).map { |i| [i.to_s, i * 2023] }.to_h,
      }
    end
    ontologies_analytics
  end
end

class TestAnalytics < LinkedData::TestCase

  def test_ontologies_analytics
    ontologies_analytics =  LinkedData::Models::Ontology.load_analytics_data
    analytics = LinkedData::Models::Ontology.analytics
    assert_equal ontologies_analytics, analytics


    month_analytics = LinkedData::Models::Ontology.analytics(2023, 1)
    refute_empty month_analytics
    month_analytics.each do |_, month_analytic|
      exp = { "2023" => { "1" => 2023 } }
      assert_equal exp, month_analytic
    end

    analytics = LinkedData::Models::Ontology.analytics(nil, nil, 'TEST')
    exp = { "TEST" => ontologies_analytics["TEST"] }
    assert_equal exp, analytics


    month_analytics = LinkedData::Models::Ontology.analytics(2021, 2, 'TEST')
    refute_empty month_analytics
    month_analytics.each do |_, month_analytic|
      exp = { "2021" => { "2" => 2 * 2021 } }
      assert_equal exp, month_analytic
    end
  end

  def test_user_analytics

    user_analytics = { 'all_users' => {
      "2021" => (1..12).map { |i| [i.to_s, i * 2021] }.to_h,
      "2022" => (1..12).map { |i| [i.to_s, i * 2022] }.to_h,
      "2023" => (1..12).map { |i| [i.to_s, i * 2023] }.to_h,
    } }
    LinkedData::Models::User.update_class_variable(user_analytics)


    analytics = LinkedData::Models::User.analytics
    assert_equal user_analytics, analytics

    month_analytics = LinkedData::Models::User.analytics(2023, 1)
    refute_empty month_analytics
    month_analytics.each do |_, month_analytic|
      exp = { "2023" => { "1" => 2023 } }
      assert_equal exp, month_analytic
    end
  end

  def test_page_visits_analytics
    user_analytics = { 'all_pages' => { "/annotator" => 229,
                                          "/mappings" => 253,
                                          "/login" => 258,
                                          "/ontologies/CSOPRA" => 273,
                                          "/admin" => 280,
                                          "/search" => 416,
                                          "/" => 4566 }
    }

    LinkedData::Models::User.update_class_variable(user_analytics)

    analytics = LinkedData::Models::User.page_visits_analytics
    assert_equal user_analytics, analytics

  end

end