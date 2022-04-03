require_relative "./test_ontology_common"
require "logger"
require "rack"

class TestOntologySubmission < LinkedData::TestOntologyCommon
  def test_get_main_concept_scheme
    submission_parse("INRAETHES",
                     "INRAETHES",
                     "./test/data/ontology_files/thesaurusINRAE_nouv_structure.skos.rdf", 1,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)
    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "INRAETHES"],
                                                       submissionId: 1)
                                                .include(:version)
                                                .first
    sub.bring_remaining
    sub.URI = "http://opendata.inrae.fr/thesaurusINRAE/thesaurusINRAE"
    sub.save
    #schemas = LinkedData::Models::Instance.where({types: RDF::URI.new(RDF::SKOS[:ConceptScheme])}).in(sub).all
    roots = sub.roots
    assert_equal  12, roots.size
    assert !sub.nil?
  end
end

