require_relative './test_ontology_common'
require 'logger'
require 'rack'

class TestOntologySubmission < LinkedData::TestOntologyCommon

  def test_skos_ontology
    submission_parse('SKOS-TEST',
                     'SKOS TEST Bla',
                     './test/data/ontology_files/efo_gwas.skos.owl', 987,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: 'SKOS-TEST'],
                                                       submissionId: 987)
                                                .include(:version)
                                                .first

    assert sub.roots.map { |x| x.id.to_s }.sort == ['http://www.ebi.ac.uk/efo/EFO_0000311',
                                                    'http://www.ebi.ac.uk/efo/EFO_0001444',
                                                    'http://www.ifomis.org/bfo/1.1/snap#Disposition',
                                                    'http://www.ebi.ac.uk/chebi/searchId.do?chebiId=CHEBI:37577',
                                                    'http://www.ebi.ac.uk/efo/EFO_0000635',
                                                    'http://www.ebi.ac.uk/efo/EFO_0000324'].sort
    roots = sub.roots
    LinkedData::Models::Class.in(sub).models(roots).include(:children).all
    roots.each do |root|
      q_broader = <<-eos
SELECT ?children WHERE {
  ?children #{RDF::SKOS[:broader].to_ntriples} #{root.id.to_ntriples} }
      eos
      children_query = []
      Goo.sparql_query_client.query(q_broader).each_solution do |sol|
        children_query << sol[:children].to_s
      end
      assert root.children.map { |x| x.id.to_s }.sort == children_query.sort
    end
  end

  def test_get_main_concept_scheme
    submission_parse('SKOS-TEST',
                     'SKOS TEST Bla',
                     './test/data/ontology_files/efo_gwas.skos.owl', 987,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)
    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: 'SKOS-TEST'],
                                                       submissionId: 987)
                                                .first

    assert_equal 'http://www.ebi.ac.uk/efo/skos/EFO_GWAS_view', sub.get_main_concept_scheme.to_s
  end
end

