require_relative "./test_ontology_common"
require "logger"
require "rack"

class TestOntologySubmission < LinkedData::TestOntologyCommon

  def setup
    LinkedData::TestCase.backend_4s_delete
  end

  def test_system_controlled_dsl_in_ontology_submission
    klass = LinkedData::Models::OntologySubmission
    attrs = klass.hypermedia_settings[:system_controlled]

    assert_includes attrs, :uploadFilePath
    assert_includes attrs, :diffFilePath
    assert attrs.all? { |a| a.is_a?(Symbol) }, "Expected all system-controlled attributes to be symbols"
  end

  def test_valid_ontology

    acronym = "BRO-TST"
    name = "SNOMED-CT TEST"
    ontologyFile = "./test/data/ontology_files/BRO_v3.2.owl"
    id = 10

    owl, bogus, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)

    os = LinkedData::Models::OntologySubmission.new
    refute os.valid?

    assert_raises ArgumentError do
      bogus.acronym = acronym
    end
    os.submissionId = id
    os.contact = [contact]
    os.released = DateTime.now - 4
    bogus.name = name
    o = LinkedData::Models::Ontology.find(acronym)
    if o.nil?
      os.ontology = LinkedData::Models::Ontology.new(:acronym => acronym)
    else
      os.ontology = o
    end
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id, ontologyFile)
    os.uploadFilePath = uploadFilePath
    os.hasOntologyLanguage = owl
    os.ontology = bogus
    os.URI = RDF::URI.new('https://test.com')
    os.description = 'description example'
    os.status = 'beta'
    assert os.valid?
  end

  def test_sanity_check_zip

    acronym = "ADARTEST"
    name = "ADARTEST Bla"
    ontologyFile = "./test/data/ontology_files/zip_missing_master_file.zip"
    id = 10

    owl, rad, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id, ontologyFile)
    ont_submision.contact = [contact]
    ont_submision.released = DateTime.now - 4
    ont_submision.URI = RDF::URI.new('https://test.com')
    ont_submision.description = 'description example'
    ont_submision.status = 'beta'
    ont_submision.uploadFilePath = uploadFilePath
    ont_submision.hasOntologyLanguage = owl
    ont_submision.ontology = rad
    refute ont_submision.valid?
    assert_equal 1, ont_submision.errors.length
    assert_instance_of Hash, ont_submision.errors[:uploadFilePath][0]
    assert_instance_of Array, ont_submision.errors[:uploadFilePath][0][:options]
    assert_instance_of String, ont_submision.errors[:uploadFilePath][0][:message]
    assert ont_submision.errors[:uploadFilePath][0][:options].length > 0
    ont_submision.masterFileName = "does not exist"
    ont_submision.valid?
    assert_instance_of Hash, ont_submision.errors[:uploadFilePath][0]
    assert_instance_of Array, ont_submision.errors[:uploadFilePath][0][:options]
    assert_instance_of String, ont_submision.errors[:uploadFilePath][0][:message]

    #choose one from options.
    ont_submision.masterFileName = ont_submision.errors[:uploadFilePath][0][:options][0]
    assert ont_submision.valid?
    assert_equal 0, ont_submision.errors.length
  end

  def test_duplicated_file_names

    acronym = "DUPTEST"
    name = "DUPTEST Bla"
    ontologyFile = "./test/data/ontology_files/ont_dup_names.zip"
    id = 10

    owl, dup, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)
    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => 1,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id, ontologyFile)
    ont_submision.contact = [contact]
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.uri = RDF::URI.new('https://test.com')
    ont_submision.description = 'description example'
    ont_submision.status = 'beta'
    ont_submision.ontology = dup
    assert (!ont_submision.valid?)
    assert_equal 1, ont_submision.errors.length
    assert_instance_of String, ont_submision.errors[:uploadFilePath][0]
  end

  def test_skos_ontology
    submission_parse("SKOS-TEST",
                     "SKOS TEST Bla",
                     "./test/data/ontology_files/efo_gwas.skos.owl", 987,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "SKOS-TEST"],
                                                       submissionId: 987)
                                                .include(:version)
                                                .first
    assert sub.roots.map { |x| x.id.to_s}.sort == ["http://www.ebi.ac.uk/efo/EFO_0000311",
                                                   "http://www.ebi.ac.uk/efo/EFO_0001444",
                                                   "http://www.ifomis.org/bfo/1.1/snap#Disposition",
                                                   "http://www.ebi.ac.uk/chebi/searchId.do?chebiId=CHEBI:37577",
                                                   "http://www.ebi.ac.uk/efo/EFO_0000635",
                                                   "http://www.ebi.ac.uk/efo/EFO_0000324"].sort
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

  def test_multiple_syn_multiple_predicate
    submission_parse("HP-TEST", "HP TEST Bla", "./test/data/ontology_files/hp.obo", 55,
                     process_rdf: true, index_search: true,
                     run_metrics: false, reasoning: true)

    #test for version info
    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "HP-TEST"],
                                                       submissionId: 55)
                                                .include(:version)
                                                .first

    paging = LinkedData::Models::Class.in(sub).page(1,100)
                                      .include(:unmapped)
    found = false

    begin
      page = paging.all
      page.each do |c|
        LinkedData::Models::Class.map_attributes(c,paging.equivalent_predicates)
        assert_instance_of(String, c.prefLabel)
        if c.id.to_s['00006']
          assert c.synonym.length == 3
          found = true
        end
      end
      paging.page(page.next_page) if page.next?
    end while(page.next?)
    assert found
  end

  def test_obo_part_of
    submission_parse("TAO-TEST", "TAO TEST Bla", "./test/data/ontology_files/tao.obo", 55,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)

    # Test for version info
    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "TAO-TEST"], submissionId: 55).include(:version).first
    assert sub.version == "2012-08-10"
    qthing = <<-eos
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT DISTINCT * WHERE {
  <http://purl.obolibrary.org/obo/TAO_0001044> rdfs:subClassOf ?x . }
    eos
    count = 0
    Goo.sparql_query_client.query(qthing).each_solution do |sol|
      count += 1
    end
    assert count == 0

    qthing = <<-eos
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  SELECT DISTINCT * WHERE {
  <http://purl.obolibrary.org/obo/TAO_0001044> <http://data.bioontology.org/metadata/treeView> ?x . }
    eos
    count = 0
    Goo.sparql_query_client.query(qthing).each_solution do |sol|
      count += 1
      assert sol[:x].to_s["TAO_0000732"]
    end
    assert count == 1

    qcount = <<-eos
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
SELECT DISTINCT * WHERE {
<http://purl.obolibrary.org/obo/TAO_0001044>
  <http://data.bioontology.org/metadata/obo/part_of> ?x . }
    eos
    count = 0
    Goo.sparql_query_client.query(qcount).each_solution do |sol|
      count += 1
      assert sol[:x].to_s["TAO_0000732"]
    end
    assert count == 1

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "TAO-TEST"]).first
    assert_equal(3, sub.roots.length, "Incorrect number of root classes")

    #strict comparison to be sure the merge with the tree_view branch goes fine

    LinkedData::Models::Class.where.in(sub).include(:prefLabel,:synonym,:notation).each do |cls|
      assert_instance_of String,cls.prefLabel
      if cls.notation.nil?
        assert false,"notation empty"
      end
      assert_instance_of String,cls.notation
      assert cls.notation[-6..-1] == cls.id.to_s[-6..-1]
      #NCBO-1007 - hasNarrowSynonym
      if cls.id.to_s["CL_0000003"]
        assert cls.synonym[0] == "cell in vivo"
      end
      #NCBO-1007 - hasBroadSynonym
      if cls.id.to_s["CL_0000137"]
        assert cls.synonym[0] == "bone cell"
      end
      #NCBO-1007 - hasRelatedSynonym
      if cls.id.to_s["TAO_0000223"]
        assert cls.synonym.length == 6
      end
    end

    # This is testing that treeView is used to traverse the hierarchy
    sub.bring(:hasOntologyLanguage)
    assert sub.hasOntologyLanguage.tree_property == Goo.vocabulary(:metadata)[:treeView]

    bm = LinkedData::Models::Class
           .find(RDF::URI.new("http://purl.obolibrary.org/obo/GO_0070977"))
           .in(sub)
           .include(:prefLabel,:children,:parents)
           .first
    assert bm.children.first.id == RDF::URI.new("http://purl.obolibrary.org/obo/GO_0043931")
    assert_equal 2, bm.parents.length
    roots = sub.roots
    assert roots.map { |x| x.id.to_s }.sort ==
             ["http://purl.obolibrary.org/obo/PATO_0000001",
              "http://purl.obolibrary.org/obo/CARO_0000000",
              "http://purl.obolibrary.org/obo/GO_0008150"].sort
  end

  def test_submission_parse_subfolders_zip
    submission_parse("CTXTEST", "CTX Bla",
                     "./test/data/ontology_files/XCTontologyvtemp2_vvtemp2.zip",
                     34,
                     masterFileName: "XCTontologyvtemp2/XCTontologyvtemp2.owl",
                     process_rdf: true, extract_metadata: false, generate_missing_labels: false)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "CTXTEST"]).first

    #test roots to ack parsing went well
    n_roots = sub.roots.length
    assert_equal 16, n_roots
  end

  def test_submission_parse
    # This one has some nasty looking IRIS with slashes in the anchor
    unless ENV["BP_SKIP_HEAVY_TESTS"] == "1"
      submission_parse("MCCLTEST", "MCCLS TEST",
                         "./test/data/ontology_files/CellLine_OWL_BioPortal_v1.0.owl", 11,
                       process_rdf: true, extract_metadata: true)

      sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "MCCLTEST"], submissionId: 11)
                                                  .include(:version, :uri, :notes).first
      assert_equal '3.0', sub.version
      assert_equal 'http://www.semanticweb.org/ontologies/2009/9/12/Ontology1255323704656.owl', sub.uri
      assert_equal ['The Breast Cancer Cell Line Ontology is licensed under the terms of the Creative Commons Attribution License version 3.0 Unported, details at http://creativecommons.org/licenses/by/3.0/'], sub.notes
    end

    version = 'Version 5.0'

    # This one has resources wih accents.
    submission_parse("ONTOMATEST",
                       "OntoMA TEST",
                       "./test/data/ontology_files/OntoMA.1.1_vVersion_1.1_Date__11-2011.OWL", 15,
                     {process_rdf: true, extract_metadata: true}, {version: version})

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "ONTOMATEST"], submissionId: 15)
                                                .include(:version, :uri, :notes).first
    # This ontology has an invalid extracted version. That version should have been discarded
    # and replaced with the original one, defined in the variable `version`
    assert_equal version, sub.version
    assert_equal 'http://www.semanticweb.org/associatedmedicine/lavima/2011/10/Ontology1.owl', sub.uri.to_s
    assert_equal ['La première ontologie déddiée aux concepts de la médecine associée'], sub.notes
  end

  def test_generate_language_preflabels
    submission_parse("D3OTEST", "DSMZ Digital Diversity Ontology Test",
                     "./test/data/ontology_files/d3o.owl", 1,
                     process_rdf: true, index_search: true, extract_metadata: false)
    res = LinkedData::Models::Class.search("prefLabel_en:Anatomic Structure", {:fq => "submissionAcronym:D3OTEST", :start => 0, :rows => 100})
    refute_equal 0, res["response"]["numFound"]
    refute_nil res["response"]["docs"].select{|doc| doc["resource_id"].eql?('https://purl.dsmz.de/schema/AnatomicStructure')}.first

    submission_parse("EPOTEST", "Early Pregnancy Ontology Test",
                     "./test/data/ontology_files/epo.owl", 1,
                     process_rdf: true, index_search: true, extract_metadata: false)
    res = LinkedData::Models::Class.search("prefLabel_en:technical element", {:fq => "submissionAcronym:EPOTEST", :start => 0, :rows => 100})
    refute_equal 0, res["response"]["numFound"]
    refute_nil res["response"]["docs"].select{|doc| doc["resource_id"].eql?('http://www.semanticweb.org/ontologies/epo.owl#OPPIO_t000000')}.first
    res = LinkedData::Models::Class.search("prefLabel_fr:éléments techniques", {:fq => "submissionAcronym:EPOTEST", :start => 0, :rows => 100})
    refute_equal 0, res["response"]["numFound"]
    refute_nil res["response"]["docs"].select{|doc| doc["resource_id"].eql?('http://www.semanticweb.org/ontologies/epo.owl#OPPIO_t000000')}.first
  end

  def test_process_submission_diff
    acronym = 'BRO'
    # Create a 1st version for BRO
    submission_parse(acronym, "BRO",
                     "./test/data/ontology_files/BRO_v3.4.owl", 1, process_rdf: false)
    # Create a later version for BRO
    submission_parse(acronym, "BRO",
                     "./test/data/ontology_files/BRO_v3.5.owl", 2, process_rdf: false, diff: true, delete: false)

    bro = LinkedData::Models::Ontology.find(acronym).include(submissions:[:submissionId,:diffFilePath]).first
    #bro.bring(:submissions)
    submissions = bro.submissions
    #submissions.each {|s| s.bring(:submissionId, :diffFilePath)}
    # Sort submissions in descending order of submissionId, extract last two submissions
    recent_submissions = submissions.sort {|a,b| b.submissionId <=> a.submissionId}[0..1]
    sub1 = recent_submissions.last  # descending order, so last is older submission
    sub2 = recent_submissions.first # descending order, so first is latest submission
    assert(sub1.submissionId < sub2.submissionId, 'submissionId is in the wrong order')
    assert(sub1.diffFilePath == nil, 'Should not create diff for older submission.')
    assert(sub2.diffFilePath != nil, 'Failed to create diff for the latest submission.')
  end

  def test_process_submission_archive

    old_threshold = LinkedData::Services::OntologySubmissionArchiver::FILE_SIZE_ZIPPING_THRESHOLD
    LinkedData::Services::OntologySubmissionArchiver.const_set(:FILE_SIZE_ZIPPING_THRESHOLD, 0)

    ont_count, ont_acronyms, ontologies =
      create_ontologies_and_submissions(ont_count: 1, submission_count: 2,
                                        process_submission: true,
                                        acronym: 'NCBO-545', process_options: {process_rdf: true, index_search: true,
                                                                               extract_metadata: false})
    # Sanity check.
    assert_equal 1, ontologies.count
    assert_equal 2, ontologies.first.submissions.count

    # Sort submissions in descending order.
    sorted_submissions = ontologies.first.submissions.sort { |a,b| b.submissionId <=> a.submissionId }

    # Process latest submission.  No files should be deleted.
    latest_sub = sorted_submissions.first
    latest_sub.process_submission(Logger.new(latest_sub.parsing_log_path), {archive: true})

    refute latest_sub.archived?

    assert File.file?(File.join(latest_sub.data_folder, 'labels.ttl')),
           %-Missing ontology submission file: 'labels.ttl'-

    assert File.file?(File.join(latest_sub.data_folder, 'owlapi.xrdf')),
           %-Missing ontology submission file: 'owlapi.xrdf'-

    assert File.file?(latest_sub.csv_path),
           %-Missing ontology submission file: '#{latest_sub.csv_path}'-

    assert File.file?(latest_sub.parsing_log_path),
           %-Missing ontology submission file: '#{latest_sub.parsing_log_path}'-

    # Process one prior to latest submission.  Some files should be deleted.
    old_sub = sorted_submissions.last
    old_file_path = old_sub.uploadFilePath
    old_sub.process_submission(Logger.new(old_sub.parsing_log_path), {archive: true})
    assert old_sub.archived?

    refute File.file?(File.join(old_sub.data_folder, 'labels.ttl')),
                 %-File deletion failed for 'labels.ttl'-

    refute File.file?(File.join(old_sub.data_folder, 'mappings.ttl')),
                 %-File deletion failed for 'mappings.ttl'-

    refute File.file?(File.join(old_sub.data_folder, 'obsolete.ttl')),
                 %-File deletion failed for 'obsolete.ttl'-

    refute File.file?(File.join(old_sub.data_folder, 'owlapi.xrdf')),
                 %-File deletion failed for 'owlapi.xrdf'-

    refute File.file?(old_sub.csv_path),
                 %-File deletion failed for '#{old_sub.csv_path}'-

    refute File.file?(old_sub.parsing_log_path),
      %-File deletion failed for '#{old_sub.parsing_log_path}'-

    refute File.file?(old_file_path),
                 %-File deletion failed for '#{old_file_path}'-

    assert old_sub.zipped?
    assert File.file?(old_sub.uploadFilePath)
    LinkedData::Models::OntologySubmission.const_set(:FILE_SIZE_ZIPPING_THRESHOLD, old_threshold)
  end

  def test_submission_diff_across_ontologies
    # Create a 1st version for BRO
    submission_parse("BRO34", "BRO3.4",
                     "./test/data/ontology_files/BRO_v3.4.owl", 1,
                     process_rdf: false)
    onts = LinkedData::Models::Ontology.find('BRO34')
    bro34 = onts.first
    bro34.bring(:submissions)
    sub34 = bro34.submissions.first
    # Create a later version for BRO
    submission_parse("BRO35", "BRO3.5",
                     "./test/data/ontology_files/BRO_v3.5.owl", 1,
                     process_rdf: false)
    onts = LinkedData::Models::Ontology.find('BRO35')
    bro35 = onts.first
    bro35.bring(:submissions)
    sub35 = bro35.submissions.first
    # Calculate the ontology diff: bro35 - bro34
    tmp_log = Logger.new($stdout)
    sub35.diff(tmp_log, sub34)
    assert(sub35.diffFilePath != nil, 'Failed to create submission diff file.')
  end

  def test_index_properties
    submission_parse("BRO", "BRO Ontology",
                     "./test/data/ontology_files/BRO_v3.5.owl", 1,
                     process_rdf: true, extract_metadata: false, index_properties: true)
    res = LinkedData::Models::Class.search("*:*", {:fq => "submissionAcronym:\"BRO\"", :start => 0, :rows => 80}, :property)
    assert_equal 84, res["response"]["numFound"]
    found = 0

    res["response"]["docs"].each do |doc|
      if doc["resource_id"] == "http://www.w3.org/2004/02/skos/core#broaderTransitive"
        found +=1
        assert_equal "ONTOLOGY", doc["ontologyType"]
        assert_equal "OBJECT", doc["propertyType"]
        assert_equal "BRO", doc["submissionAcronym"]
        assert_equal ["has broader transitive"], doc["label"]
        assert_equal ["broadertransitive", "broader transitive"], doc["labelGenerated"]
        assert_equal 1, doc["submissionId"]
      elsif doc["resource_id"] == "http://bioontology.org/ontologies/biositemap.owl#contact_person_email"
        found +=1
        assert_equal "DATATYPE", doc["propertyType"]
        assert_equal "BRO", doc["submissionAcronym"]
        assert_nil doc["label"]
        assert_equal ["contact_person_email", "contact person email"], doc["labelGenerated"]
        assert_equal "http://data.bioontology.org/ontologies/BRO/submissions/1", doc["ontologyId"]
      end

      break if found == 2
    end

    assert_equal 2, found # if owliap does not import skos properties
    ont = LinkedData::Models::Ontology.find('BRO').first
    ont.unindex_properties(true)


    res = LinkedData::Models::Class.search("*:*", {:fq => "submissionAcronym:\"BRO\""},:property)
    assert_equal 0, res["response"]["numFound"]
  end

  def test_index_multilingual
    submission_parse("BRO", "BRO Ontology",
                     "./test/data/ontology_files/BRO_v3.5.owl", 1,
                     process_rdf: true, extract_metadata: false, generate_missing_labels: false,
                     index_search: true, index_properties: false)

    res = LinkedData::Models::Class.search("prefLabel:Activity", {:fq => "submissionAcronym:BRO", :start => 0, :rows => 80})
    refute_equal 0, res["response"]["numFound"]

    doc = res["response"]["docs"].select{|doc| doc["resource_id"].to_s.eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first
    refute_nil doc
    assert_equal 30, doc.keys.select{|k| k['prefLabel'] || k['synonym']}.size # test that all the languages are indexed

    res = LinkedData::Models::Class.search("prefLabel_none:Activity", {:fq => "submissionAcronym:BRO", :start => 0, :rows => 80})
    refute_equal 0, res["response"]["numFound"]
    refute_nil res["response"]["docs"].select{|doc| doc["resource_id"].eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first

    res = LinkedData::Models::Class.search("prefLabel_fr:Activité", {:fq => "submissionAcronym:BRO", :start => 0, :rows => 80})
    refute_equal 0, res["response"]["numFound"]
    refute_nil res["response"]["docs"].select{|doc| doc["resource_id"].eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first

    res = LinkedData::Models::Class.search("prefLabel_en:ActivityEnglish", {:fq => "submissionAcronym:BRO", :start => 0, :rows => 80})
    refute_equal 0, res["response"]["numFound"]
    refute_nil res["response"]["docs"].select{|doc| doc["resource_id"].eql?('http://bioontology.org/ontologies/Activity.owl#Activity')}.first

    res = LinkedData::Models::Class.search("prefLabel_fr:Activity", {:fq => "submissionAcronym:BRO", :start => 0, :rows => 80})
    assert_equal 0, res["response"]["numFound"]

    res = LinkedData::Models::Class.search("prefLabel_ja:カタログ", {:fq => "submissionAcronym:BRO", :start => 0, :rows => 80})
    refute_equal 0, res["response"]["numFound"]
    refute_nil res["response"]["docs"].select{|doc| doc["resource_id"].eql?('http://bioontology.org/ontologies/Activity.owl#Catalog')}.first
  end

  def test_submission_parse_multilingual
    acronym = 'D3O'
    submission_parse(acronym, "D3O TEST",
                     "./test/data/ontology_files/dcat3.rdf", 1,
                     process_rdf: true, extract_metadata: false)
    ont = LinkedData::Models::Ontology.find(acronym).include(:acronym).first
    sub = ont.latest_submission
    sub.bring_remaining

    cl = LinkedData::Models::Class.find('http://www.w3.org/ns/dcat#DataService').in(sub).first
    cl.bring(:prefLabel)
    assert_equal 'Data service', cl.prefLabel

    RequestStore.store[:requested_lang] = :ALL
    cl = LinkedData::Models::Class.find('http://www.w3.org/ns/dcat#DataService').in(sub).first
    cl.bring(:prefLabel)
    prefLabels = cl.prefLabel(include_languages: true)
    assert_equal 'Data service', prefLabels[:en]
    assert_equal 'Datatjeneste', prefLabels[:da]
    assert_equal 'Servicio de datos', prefLabels[:es]
    assert_equal 'Servizio di dati', prefLabels[:it]
    RequestStore.store[:requested_lang] = nil
  end

  def test_zipped_submission_process
    acronym = "PIZZA"
    name = "PIZZA Ontology"
    ontologyFile = "./test/data/ontology_files/pizza.owl.zip"
    archived_submission = nil
    2.times do |i|
      id = 20 + i
      ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id})
      assert (not ont_submision.valid?)
      assert_equal 4, ont_submision.errors.length
      uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
      ont_submision.uploadFilePath = uploadFilePath
      owl, bro, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)
      ont_submision.released = DateTime.now - 4
      ont_submision.hasOntologyLanguage = owl
      ont_submision.ontology = bro
      ont_submision.contact = [contact]
      ont_submision.URI = RDF::URI.new("https://test-#{id}.com")
      ont_submision.description =  "Description #{id}"
      ont_submision.status = 'production'
      assert ont_submision.valid?
      ont_submision.save
      parse_options = {process_rdf: false, diff: true}
      begin
        tmp_log = Logger.new(TestLogFile.new)
        ont_submision.process_submission(tmp_log, parse_options)
      rescue Exception => e
        puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
        raise e
      end
      archived_submission = ont_submision if i.zero?
    end
    parse_options = { process_rdf: false,  archive: true }
    archived_submission.process_submission(Logger.new(TestLogFile.new), parse_options)

    assert_equal false, File.file?(archived_submission.zip_folder),
                 %-File deletion failed for '#{archived_submission.zip_folder}'-
  end

  def test_submission_parse_zip
    skip if ENV["BP_SKIP_HEAVY_TESTS"] == "1"

    # acronym = "RADTEST"
    # name = "RADTEST Bla"
    # ontologyFile = "./test/data/ontology_files/radlex_owl_v3.0.1a.zip"

    acronym = "PIZZA"
    name = "PIZZA Ontology"
    ontologyFile = "./test/data/ontology_files/pizza.owl.zip"
    id = 10

    LinkedData::TestCase.backend_4s_delete

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    ont_submision.uri = RDF::URI.new('https://test.com')
    ont_submision.description = 'description example'
    ont_submision.status = 'beta'
    assert (not ont_submision.valid?)
    assert_equal 4, ont_submision.errors.length
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
    ont_submision.uploadFilePath = uploadFilePath
    owl, bro, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.prefLabelProperty = RDF::URI.new("http://bioontology.org/projects/ontologies/radlex/radlexOwl#Preferred_name")
    ont_submision.ontology = bro
    ont_submision.contact = [contact]
    assert (ont_submision.valid?)
    ont_submision.save
    parse_options = {process_rdf: true, reasoning: true, index_search: false, run_metrics: false, diff: false}
    begin
      tmp_log = Logger.new(TestLogFile.new)
      ont_submision.process_submission(tmp_log, parse_options)
    rescue Exception => e
      puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
      raise e
    end

    assert ont_submision.ready?({status: [:uploaded, :rdf, :rdf_labels]})
    read_only_classes = LinkedData::Models::Class.in(ont_submision).include(:prefLabel).read_only
    ctr = 0

    read_only_classes.each do |cls|
      # binding.pry
      # binding.pry if cls.prefLabel.nil?
      # next if cls.id.to_s == "http://bioontology.org/projects/ontologies/radlex/radlexOwl#neuraxis_metaclass"
      # next if cls.id.to_s == "http://bioontology.org/projects/ontologies/radlex/radlexOwl#RID7020"
      # assert(cls.prefLabel != nil, "Class #{cls.id.to_ntriples} does not have a label")
      if cls.prefLabel.nil?
        puts "Class #{cls.id.to_ntriples} does not have a label"
        ctr += 1
      end
      # assert_instance_of String, cls.prefLabel
    end
    puts "#{ctr} classes with no label"
  end

  def test_submission_parse_gzip
    skip if ENV["BP_SKIP_HEAVY_TESTS"] == "1"

    acronym = "BROGZ"
    name = "BRO GZIPPED"
    ontologyFile = "./test/data/ontology_files/BRO_v3.2.owl.gz"
    id = 11

    LinkedData::TestCase.backend_4s_delete

    ont_submission = LinkedData::Models::OntologySubmission.new({submissionId: id})
    refute ont_submission.valid?
    assert_equal 4, ont_submission.errors.length
    upload_file_path = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id, ontologyFile)
    ont_submission.uploadFilePath = upload_file_path
    owl, bro, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)
    ont_submission.released = DateTime.now - 4
    ont_submission.hasOntologyLanguage = owl
    ont_submission.prefLabelProperty = RDF::URI.new("http://bioontology.org/projects/ontologies/radlex/radlexOwl#Preferred_name")
    ont_submission.ontology = bro
    ont_submission.contact = [contact]
    assert ont_submission.valid?
    ont_submission.save
    parse_options = {process_rdf: true, reasoning: true, index_search: false, run_metrics: false, diff: false}
    begin
      tmp_log = Logger.new(TestLogFile.new)
      ont_submission.process_submission(tmp_log, parse_options)
    rescue StandardError => e
      puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
      raise e
    end

    assert ont_submission.ready?({status: [:uploaded, :rdf, :rdf_labels]})
    read_only_classes = LinkedData::Models::Class.in(ont_submission).include(:prefLabel).read_only
    refute read_only_classes.empty?
  end

  def test_download_ontology_file
    begin
      server_url, server_thread, server_port  = start_server
      sleep 3  # Allow the server to startup
      assert(server_thread.alive?, msg="Rack::Server thread should be alive, it's not!")
      ont_count, ont_names, ont_models = create_ontologies_and_submissions(ont_count: 1, submission_count: 1)
      ont = ont_models.first
      assert(ont.instance_of?(LinkedData::Models::Ontology), "ont is not an ontology: #{ont}")
      sub = ont.bring(:submissions).submissions.first
      assert(sub.instance_of?(LinkedData::Models::OntologySubmission), "sub is not an ontology submission: #{sub}")
      sub.pullLocation = RDF::IRI.new(server_url)
      file, filename = sub.download_ontology_file
      sleep 2
      assert filename.nil?, "Test filename is not nil: #{filename}"
      assert file.is_a?(Tempfile), "Test file is not a Tempfile"
      file.open
      assert file.read.eql?("test file"), "Test file content error: #{file.read}"
    ensure
      LinkedData::TestCase.backend_4s_delete
      Thread.kill(server_thread)  # this will shutdown Rack::Server also
      sleep 3
      assert_equal(server_thread.alive?, false, msg="Rack::Server thread should be dead, it's not!")
    end
  end

  def test_semantic_types
    acronym = 'STY-TST'
    submission_parse(acronym, "STY Bla", "./test/data/ontology_files/umls_semantictypes.ttl", 1,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)
    ont_sub = LinkedData::Models::Ontology.find(acronym).first.latest_submission(status: [:rdf])
    classes = LinkedData::Models::Class.in(ont_sub).include(:prefLabel).read_only.to_a
    assert_equal 133, classes.length
    classes.each do |cls|
      assert(cls.prefLabel != nil, "Class #{cls.id.to_ntriples} does not have a label")
      assert_instance_of String, cls.prefLabel
    end
  end

  def test_umls_metrics_file
    acronym = 'UMLS-TST'
    submission_parse(acronym, "Test UMLS Ontologory", "./test/data/ontology_files/umls_semantictypes.ttl", 1,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)
    sub = LinkedData::Models::Ontology.find(acronym).first.latest_submission(status: [:rdf])
    metrics = sub.metrics_from_file(Logger.new(sub.parsing_log_path))
    assert !metrics.nil?, "Metrics is nil: #{metrics}"
    assert !metrics.empty?, "Metrics is empty: #{metrics}"
    metrics.each { |m| assert_equal 4, m.length }
    assert_equal "Individual Count", metrics[0][1]
    assert_equal 133, metrics[1][0].to_i
  end

  def test_discover_obo_in_owl_obsolete
    acr = "OBSPROPSDISCOVER"
    init_test_ontology_msotest acr

    o = LinkedData::Models::Ontology.find(acr).first
    o.bring_remaining
    o.bring(:submissions)
    oss = o.submissions
    assert_equal 1, oss.length
    ont_sub = oss.first
    ont_sub.bring_remaining
    assert ont_sub.ready?
    classes = LinkedData::Models::Class.in(ont_sub).include(:prefLabel, :synonym, :obsolete).to_a
    classes.each do |c|
      assert (not c.prefLabel.nil?)
      if c.id.to_s["OBS"] || c.id.to_s["class6"]
        assert(c.obsolete, "Class should be obsolete: #{c.id}")
      else
        assert_equal(false, c.obsolete, "Class should not be obsolete: #{c.id}")
      end
    end
  end

  def test_custom_obsolete_property

    acr = "OBSPROPS"
    init_test_ontology_msotest acr

    o = LinkedData::Models::Ontology.find(acr).first
    o.bring_remaining
    o.bring(:submissions)
    oss = o.submissions
    assert_equal 1, oss.length
    ont_sub = oss.first
    ont_sub.bring_remaining
    assert ont_sub.ready?
    classes = LinkedData::Models::Class.in(ont_sub).include(:prefLabel, :synonym, :obsolete).to_a
    classes.each do |c|
      assert (not c.prefLabel.nil?)
      if c.id.to_s["#class6"] || c.id.to_s["#class1"] || c.id.to_s["#class99"] || c.id.to_s["OBS"]
        assert(c.obsolete, "Class should be obsolete: #{c.id}")
      else
        assert_equal(false, c.obsolete, "Class should not be obsolete: #{c.id}")
      end
    end
  end

  def test_custom_obsolete_branch

    acr = "OBSBRANCH"
    init_test_ontology_msotest acr

    o = LinkedData::Models::Ontology.find(acr).first
    o.bring_remaining
    o.bring(:submissions)
    oss = o.submissions
    assert_equal 1, oss.length
    ont_sub = oss[0]
    ont_sub.bring_remaining
    assert ont_sub.ready?
    classes = LinkedData::Models::Class.in(ont_sub).include(:prefLabel, :synonym, :obsolete).to_a
    classes.each do |c|
      assert (not c.prefLabel.nil?)
      if c.id.to_s["#class2"] || c.id.to_s["#class6"] || c.id.to_s["#class_5"] || c.id.to_s["#class_7"]
        assert(c.obsolete, "Class should be obsolete: #{c.id}")
      else
        assert_equal(false, c.obsolete, "Class should not be obsolete: #{c.id}")
      end
    end
  end

  def test_custom_property_generation

    acr = "CSTPROPS"
    init_test_ontology_msotest acr

    o = LinkedData::Models::Ontology.find(acr).first
    o.bring_remaining
    o.bring(:submissions)
    oss = o.submissions
    assert_equal 1, oss.length
    ont_sub = oss[0]
    ont_sub.bring_remaining
    assert ont_sub.ready?
    LinkedData::Models::Class.in(ont_sub).include(:prefLabel,:synonym).read_only.each do |c|
      assert (not c.prefLabel.nil?)
      assert_instance_of String, c.prefLabel
      if c.id.to_s.include? "class6"
        #either the RDF label of the synonym
        assert ("rdfs label value" == c.prefLabel || "syn for class 6" == c.prefLabel)
      end
      if c.id.to_s.include? "class3"
        assert_equal "class3", c.prefLabel
      end
      if c.id.to_s.include? "class1"
        assert_equal "class 1 literal", c.prefLabel
      end
    end
  end

  def test_submission_root_classes
    acr = "CSTPROPS"
    init_test_ontology_msotest acr
    os = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acr ], submissionId: 1)
                                               .include(LinkedData::Models::OntologySubmission.attributes).all
    assert(os.length == 1)
    os = os[0]
    roots = os.roots

    assert_instance_of(Array, roots)
    assert_equal(6, roots.length)
    root_ids_arr = ["http://bioportal.bioontology.org/ontologies/msotes#class1",
                    "http://bioportal.bioontology.org/ontologies/msotes#class4",
                    "http://bioportal.bioontology.org/ontologies/msotes#class3",
                    "http://bioportal.bioontology.org/ontologies/msotes#class6",
                    "http://bioportal.bioontology.org/ontologies/msotes#class98",
                    "http://bioportal.bioontology.org/ontologies/msotes#class97"]
    root_ids = root_ids_arr.dup

    # class 3 is now subClass of some anonymous thing.
    # "http://bioportal.bioontology.org/ontologies/msotes#class3"]
    roots.each do |r|
      assert(root_ids.include? r.id.to_s)
      root_ids.delete_at(root_ids.index(r.id.to_s))
    end

    # all have been found
    assert_empty root_ids

    # test paginated mode
    root_ids = root_ids_arr.dup
    roots = os.roots(nil, 1, 2)
    assert_instance_of(Goo::Base::Page, roots)
    assert_equal 2, roots.length
    assert_equal 3, roots.total_pages

    roots.each do |r|
      assert(root_ids.include? r.id.to_s)
      root_ids.delete_at(root_ids.index(r.id.to_s))
    end

    assert_equal 4, root_ids.length

    roots = os.roots(nil, 2, 3)
    assert_equal 3, roots.length

    roots = os.roots(nil, 1, 300)
    assert_equal 6, roots.length
  end

  #escaping sequences
  def test_submission_parse_sbo
    acronym = "SBO-TST"
    name = "SBO Bla"
    ontologyFile = "./test/data/ontology_files/SBO.obo"
    id = 10

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id })
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
    ont_submision.uploadFilePath = uploadFilePath
    owl, sbo, user, contact = submission_dependent_objects("OBO", acronym, "test_linked_models", name)
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.contact = [contact]
    ont_submision.ontology = sbo
    ont_submision.uri = RDF::URI.new('https://test.com')
    ont_submision.description = 'description example'
    ont_submision.status = 'beta'
    assert (ont_submision.valid?)
    ont_submision.save
    assert_equal true, ont_submision.exist?(reload=true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acronym ], submissionId: id).all
    sub = sub[0]
    parse_options = {process_rdf: true, extract_metadata: false}
    begin
      tmp_log = Logger.new(TestLogFile.new)
      sub.process_submission(tmp_log, parse_options)
    rescue Exception => e
      puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
      raise e
    end
    assert sub.ready?({status: [:uploaded, :rdf, :rdf_labels]})
    page_classes = LinkedData::Models::Class.in(sub)
                                            .page(1,1000)
                                            .include(:prefLabel, :synonym).all
    page_classes.each do |c|
      if c.id.to_s == "http://purl.obolibrary.org/obo/SBO_0000004"
        assert c.prefLabel == "modelling framework"
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/SBO_0000011"
        assert c.prefLabel == "product"
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/SBO_0000236"
        assert c.prefLabel == "physical entity representation"
        assert c.synonym[0] == "new synonym"
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/SBO_0000306"
        assert c.prefLabel == "pK"
        assert c.synonym[0] == "dissociation potential"
      end
    end

  end

  #ontology with import errors
  def test_submission_parse_cno
    acronym = "CNO-TST"
    name = "CNO Bla"
    ontologyFile = "./test/data/ontology_files/CNO_05.owl"
    id = 10


    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
    ont_submision.uploadFilePath = uploadFilePath
    owl, cno, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)
    ont_submision.released = DateTime.now - 4
    ont_submision.hasOntologyLanguage = owl
    ont_submision.ontology = cno
    ont_submision.uri = RDF::URI.new('https://test.com')
    ont_submision.description = 'description example'
    ont_submision.status = 'beta'
    ont_submision.contact = [contact]
    assert (ont_submision.valid?)
    ont_submision.save

    sub = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acronym ], submissionId: id).all
    sub = sub[0]
    #this is the only ontology that indexes and tests for no error
    parse_options = {process_rdf: true, extract_metadata: false}
    begin
      tmp_log = Logger.new(TestLogFile.new)
      sub.process_submission(tmp_log, parse_options)
    rescue Exception => e
      puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
      raise e
    end
    assert sub.ready?({status: [:uploaded, :rdf, :rdf_labels]})

    #make sure no errors in statuses
    sub.submissionStatus.select { |x| x.id.to_s["ERROR"] }.length == 0

    LinkedData::Models::Class.where.in(sub)
                             .include(:prefLabel, :notation, :prefixIRI).each do |cls|
      assert !cls.notation.nil? || !cls.prefixIRI.nil?
      assert !cls.id.to_s.start_with?(":")
    end

  end

  #multiple preflables
  def test_submission_parse_aero
    skip "Re-enable when NCBO-851 is resolved"

    acronym = "AERO-TST"
    name = "aero Bla"
    ontologyFile = "./test/data/ontology_files/aero.owl"
    id = 10

    LinkedData::TestCase.backend_4s_delete

    ont_submision =  LinkedData::Models::OntologySubmission.new({ :submissionId => id,})
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id,ontologyFile)
    ont_submision.uploadFilePath = uploadFilePath
    owl, aero, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)
    ont_submision.released = DateTime.now - 4
    ont_submision.prefLabelProperty =  RDF::URI.new "http://www.w3.org/2000/01/rdf-schema#label"
    ont_submision.synonymProperty = RDF::URI.new "http://purl.obolibrary.org/obo/IAO_0000118"
    ont_submision.definitionProperty = RDF::URI.new "http://purl.obolibrary.org/obo/IAO_0000115"
    ont_submision.authorProperty = RDF::URI.new "http://purl.obolibrary.org/obo/IAO_0000117"
    ont_submision.hasOntologyLanguage = owl
    ont_submision.contact = [contact]
    ont_submision.ontology = aero
    assert (ont_submision.valid?)
    ont_submision.save
    assert_equal true, ont_submision.exist?(reload=true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [ acronym: acronym ], submissionId: id).all
    sub = sub[0]
    parse_options = {process_rdf: true, index_search: false, run_metrics: false, reasoning: true}
    begin
      tmp_log = Logger.new(TestLogFile.new)
      sub.process_submission(tmp_log, parse_options)
    rescue Exception => e
      puts "Error, logged in #{tmp_log.instance_variable_get("@logdev").dev.path}"
      raise e
    end
    assert sub.ready?({status: [:uploaded, :rdf, :rdf_labels]})
    sparql_query = <<eos
SELECT * WHERE {
GRAPH <http://data.bioontology.org/ontologies/AERO-TST/submissions/10>
{ <http://purl.obolibrary.org/obo/AERO_0000001>
   <http://www.w3.org/2004/02/skos/core#notation> ?o
   }}
eos
    count_notation = 0
    Goo.sparql_query_client.query(sparql_query).each_solution do |sol|
      assert sol[:o].object == "CODE000001"
      count_notation += 1
    end
    assert count_notation == 1
    count_notation = 0
    sparql_query = <<eos
SELECT * WHERE {
GRAPH <http://data.bioontology.org/ontologies/AERO-TST/submissions/10>
{ <http://purl.obolibrary.org/obo/AERO_0000001>
   <http://data.bioontology.org/metadata/prefixIRI> ?o
   }}
eos
    count_notation = 0
    Goo.sparql_query_client.query(sparql_query).each_solution do |sol|
      assert true == false
      count_notation += 1
    end
    assert count_notation == 0
    #test for ontology headers added to the graph
    sparql_query = <<eos
SELECT * WHERE {
GRAPH <http://data.bioontology.org/ontologies/AERO-TST/submissions/10>
{ <http://purl.obolibrary.org/obo/aero.owl> ?p ?o .}}
eos
    count_headers = 0
    Goo.sparql_query_client.query(sparql_query).each_solution do |sol|
      count_headers += 1
      assert sol[:p].to_s["contributor"] || sol[:p].to_s["comment"]
    end
    assert count_headers > 2

    page_classes = LinkedData::Models::Class.in(sub)
                                            .page(1,1000)
                                            .read_only
                                            .include(:prefLabel, :synonym, :definition).all
    page_classes.each do |c|
      if c.id.to_s == "http://purl.obolibrary.org/obo/AERO_0000040"
        assert c.prefLabel == "shaking finding"
        assert c.synonym.sort == ["trembling", "tremor", "quivering", "shivering"].sort
        assert !c.definition[0]["repetitive, cyclical movements of the body or"].nil?
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/UBERON_0004535"
        assert c.prefLabel == "UBERON_0004535"
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/ogms/OMRE_0000105"
        assert c.prefLabel == "OMRE_0000105"
      end
      if c.id.to_s == "http://purl.obolibrary.org/obo/UBERON_0012125"
        assert c.prefLabel = "UBERON_0012125"
      end
    end

    #for indexing in search
    paging = LinkedData::Models::Class.in(sub).page(1,100)
                                      .include(:unmapped)
    page = nil
    defs = 0
    syns = 0
    begin
      page = paging.all
      page.each do |c|
        LinkedData::Models::Class.map_attributes(c,paging.equivalent_predicates)
        assert_instance_of(String, c.prefLabel)
        syns += c.synonym.length
        defs += c.definition.length
      end
      paging.page(page.next_page) if page.next?
    end while(page.next?)
    assert syns == 5
    assert defs == 49
    LinkedData::TestCase.backend_4s_delete
  end

  def test_submission_metrics
    submission_parse("CDAOTEST", "CDAOTEST testing metrics",
                     "./test/data/ontology_files/cdao_vunknown.owl", 22,
                     process_rdf: true, run_metrics: true, extract_metadata: false)
    sub = LinkedData::Models::Ontology.find("CDAOTEST").first.latest_submission(status: [:rdf, :metrics])
    sub.bring(:metrics)

    metrics = sub.metrics
    metrics.bring_remaining
    assert_instance_of LinkedData::Models::Metric, metrics

    assert_equal 165, metrics.classes
    assert_equal 78, metrics.properties
    assert_equal 26, metrics.individuals
    assert_equal 15, metrics.classesWithOneChild
    assert_equal 139, metrics.classesWithNoDefinition
    assert_equal 0, metrics.classesWithMoreThan25Children
    assert_equal 18, metrics.maxChildCount
    assert_equal 3, metrics.averageChildCount
    assert_equal 4, metrics.maxDepth

    submission_parse("BROTEST-METRICS", "BRO testing metrics",
                     "./test/data/ontology_files/BRO_v3.2.owl", 33,
                     process_rdf: true, extract_metadata: false,
                     run_metrics: true)
    sub = LinkedData::Models::Ontology.find("BROTEST-METRICS").first.latest_submission(status: [:rdf, :metrics])
    sub.bring(:metrics)

    LinkedData::Models::Class.where.in(sub).include(:prefixIRI).each do |cls|
      if cls.id.to_s["Material_Resource"] || cls.id.to_s["People_Resource"]
        next
      end
      assert !cls.prefixIRI.nil?
      assert cls.prefixIRI.is_a?(String)
      assert (!cls.prefixIRI.start_with?(":")) || (cls.prefixIRI[":"] != nil)
      cindex = (cls.prefixIRI.index ":") || 0
      assert cls.id.end_with?(cls.prefixIRI[cindex+1..-1])
    end

    metrics = sub.metrics
    metrics.bring_remaining
    assert_instance_of LinkedData::Models::Metric, metrics

    assert_includes [481, 487], metrics.classes # 486 if owlapi imports skos classes
    assert_includes [63, 45], metrics.properties # 63 if owlapi imports skos properties
    assert_equal 124, metrics.individuals
    assert_includes [13, 14], metrics.classesWithOneChild # 14 if owlapi imports skos properties
    assert_includes [473, 474], metrics.classesWithNoDefinition # 474 if owlapi imports skos properties
    assert_equal 2, metrics.classesWithMoreThan25Children
    assert_equal 65, metrics.maxChildCount
    assert_equal 5, metrics.averageChildCount
    assert_equal 7, metrics.maxDepth

    submission_parse("BROTEST-ISFLAT", "BRO testing metrics flat",
                     "./test/data/ontology_files/BRO_v3.2.owl", 33,
                     process_rdf: true, extract_metadata: false,
                     run_metrics: true)

    sub = LinkedData::Models::Ontology.find("BROTEST-ISFLAT").first
                                      .latest_submission(status: [:rdf, :metrics])
    sub.bring(:metrics)
    metrics = sub.metrics
    metrics.bring_remaining

    #all the child metrics should be 0 since we declare it as flat
    assert_equal 487, metrics.classes
    assert_equal 63, metrics.properties
    assert_equal 124, metrics.individuals
    assert_equal 0, metrics.classesWithOneChild
    assert_equal 7, metrics.maxDepth
    #cause it has not the subproperty added
    assert_equal 474, metrics.classesWithNoDefinition
    assert_equal 0, metrics.classesWithMoreThan25Children
    assert_equal 0, metrics.maxChildCount
    assert_equal 0, metrics.averageChildCount

    #test UMLS metrics
    acronym = 'UMLS-TST'
    submission_parse(acronym, "Test UMLS Ontologory", "./test/data/ontology_files/umls_semantictypes.ttl", 1,
                     process_rdf: true, extract_metadata: false,
                     run_metrics: true)
    sub = LinkedData::Models::Ontology.find(acronym).first.latest_submission(status: [:rdf, :metrics])
    sub.bring(:metrics)
    metrics = sub.metrics
    metrics.bring_remaining
    assert_equal 133, metrics.classes
  end

  # See https://github.com/ncbo/ncbo_cron/issues/82#issuecomment-3104054081
  def test_disappearing_values
    acronym = "ONTOMATEST"
    name = "ONTOMA Test Ontology"
    ontologyFile = "./test/data/ontology_files/OntoMA.1.1_vVersion_1.1_Date__11-2011.OWL"

    id = 15
    ont_submission =  LinkedData::Models::OntologySubmission.new({ :submissionId => id})
    assert (not ont_submission.valid?)
    assert_equal 4, ont_submission.errors.length
    uploadFilePath = LinkedData::Models::OntologySubmission.copy_file_repository(acronym, id, ontologyFile)
    ont_submission.uploadFilePath = uploadFilePath
    owl, ontoma, user, contact = submission_dependent_objects("OWL", acronym, "test_linked_models", name)
    ont_submission.released = DateTime.now - 4
    ont_submission.hasOntologyLanguage = owl
    ont_submission.ontology = ontoma
    ont_submission.contact = [contact]
    ont_submission.uri = RDF::URI.new("https://test-#{id}.com")
    ont_submission.description =  "Description #{id}"
    ont_submission.status = 'production'
    old_version = 'Version 5.0'
    ont_submission.version = old_version

    assert ont_submission.valid?
    ont_submission.save

    logger = Logger.new(TestLogFile.new)
    ont_submission.generate_rdf(logger, reasoning: true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "ONTOMATEST"], submissionId: 15).include(:version).first
    puts "Version should be equal to \"#{old_version}\". The value is: \"#{sub.version}\""
    assert_equal old_version, sub.version, "Version should be equal to: \"#{old_version}\", but it is equal to: \"#{sub.version}\""

    # Make sure, :previous_values has an entry :version.
    # Until this bug is resolved, :previous_values is forcibly
    # reset inside ont_submission.generate_rdf() to handle this bug
    ont_submission.previous_values[:version] = old_version
    # Set ANY attribute in the submission. Status is picked as an example
    ont_submission.status = 'pre-production'
    ont_submission.save

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "ONTOMATEST"], submissionId: 15).include(:version).first
    puts "Due to a bug, the version became nil. The value is: #{sub.version.nil? ? "nil" : '"' + sub.version + '"'}"
    assert_nil sub.version, "Due to a bug, the version should be nil, but it is equal to: \"#{sub.version}\""
  end

  # To test extraction of metadata when parsing a submission (we extract the submission attributes that have the
  # extractedMetadata on true)
  def test_submission_extract_metadata
    acronym = "AGROOE"
    2.times.each do |i|
      submission_parse(acronym, "#{acronym} Test extract metadata ontology",
                       "./test/data/ontology_files/agrooeMappings-05-05-2016.owl", i + 1,
                       process_rdf: true, extract_metadata: true, generate_missing_labels: false)
      sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: acronym], submissionId: i + 1)
                                                  .include(:description).first
      refute_nil sub

      sub.bring_remaining
      assert_equal false, sub.deprecated
      assert_equal '2015-09-28', sub.creationDate.to_date.to_s
      assert_equal '2015-10-01', sub.modificationDate.to_date.to_s
      assert_equal "description example,  AGROOE is an ontology used to test the metadata extraction,  AGROOE is an ontology to illustrate how to describe their ontologies", sub.description
      assert_equal [RDF::URI.new('http://agroportal.lirmm.fr')], sub.identifier
      assert_equal ["http://lexvo.org/id/iso639-3/fra", "http://lexvo.org/id/iso639-3/eng"].sort, sub.naturalLanguage.sort
      assert_equal [RDF::URI.new("http://lirmm.fr/2015/ontology/door-relation.owl"),
                    RDF::URI.new("http://lirmm.fr/2015/ontology/dc-relation.owl"),
                    RDF::URI.new("http://lirmm.fr/2015/ontology/dcterms-relation.owl"),
                    RDF::URI.new("http://lirmm.fr/2015/ontology/voaf-relation.owl"),
                    RDF::URI.new("http://lirmm.fr/2015/ontology/void-import.owl")
                   ].sort, sub.ontologyRelatedTo.sort
      # assert_equal ["Agence 007", "Éditions \"La Science en Marche\"", " LIRMM (default name) "].sort, sub.publisher.map { |x| x.bring_remaining.name }.sort
      # assert_equal ["Alfred DC", "Clement Jonquet", "Gaston Dcterms", "Huguette Doap", "Mirabelle Prov", "Paul Foaf", "Vincent Emonet"].sort, sub.hasCreator.map { |x| x.bring_remaining.name }.sort
      # assert_equal ["Léontine Dessaiterm", "Anne Toulet", "Benjamine Dessay", "Augustine Doap", "Vincent Emonet"].sort, sub.hasContributor.map { |x| x.bring_remaining.name }.sort
      # assert_equal 1, LinkedData::Models::Agent.where(name: "Vincent Emonet").count
    end
  end

  def test_submission_delete_remove_files
    #This one has resources wih accents.
    submission_parse("ONTOMATEST",
                     "OntoMA TEST",
                     "./test/data/ontology_files/OntoMA.1.1_vVersion_1.1_Date__11-2011.OWL", 15,
                     process_rdf: false)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: "ONTOMATEST"],
                                                       submissionId: 15)
                                                .first

    data_folder = sub.data_folder
    assert Dir.exist? data_folder
    sub.delete
    assert !Dir.exist?(data_folder)
  end

  def test_copy_file_repository_from_tempfile
    # Simulate a Rack Tempfile upload from tmpdir;
    # tmpfile get 0600 permission and we need 660 for the copy to repository
    fixture = "./test/data/ontology_files/BRO_v3.2.owl"
    tmp     = Tempfile.new(["upload", ".owl"])
    begin
      FileUtils.cp(fixture, tmp.path)
      tmp.close

      # Assert the source Tempfile has default 0600 permissions
      # `& 0o777` is a bitwise AND that out all non-permission bits
      # convers 0o100600 (regular file with owner rw) to 0600
      src_mode = File.stat(tmp.path).mode & 0o0777
      assert_equal 0o0600, src_mode

      dst = LinkedData::Models::OntologySubmission
        .copy_file_repository("TMPTEST", 99, tmp.path)

      repo_root = LinkedData.settings.repository_folder
      assert_match(
        %r{\A#{Regexp.escape(repo_root)}/TMPTEST/99/},
        dst,
        "Expected file to be copied into #{repo_root}/TMPTEST/99/"
      )
      assert File.exist?(dst), "Destination file should exist"

      mode = File.stat(dst).mode & 0o0777
      assert_equal 0o0660, mode, format("Expected file mode 0660, got %o", mode)
    ensure
      tmp.unlink
    end
  end

end
