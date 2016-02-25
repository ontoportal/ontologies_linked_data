module LinkedData
module Mappings

  def self.mapping_predicates()
    predicates = {}
    predicates["CUI"] = ["http://bioportal.bioontology.org/ontologies/umls/cui"]
    predicates["SAME_URI"] =
      ["http://data.bioontology.org/metadata/def/mappingSameURI"]
    predicates["LOOM"] =
      ["http://data.bioontology.org/metadata/def/mappingLoom"]
    predicates["REST"] =
      ["http://data.bioontology.org/metadata/def/mappingRest"]
    return predicates
  end

  def self.retrieve_latest_submissions()
    status = "RDF"
    include_ready = status.eql?("READY") ? true : false
    status = "RDF" if status.eql?("READY")
    includes = []
    includes << :submissionStatus
    includes << :submissionId
    includes << { ontology: [:acronym, :viewOf] }
    submissions_query = LinkedData::Models::OntologySubmission
                          .where(submissionStatus: [ code: status])

    filter = Goo::Filter.new(ontology: [:viewOf]).unbound
    submissions_query = submissions_query.filter(filter)
    submissions = submissions_query.include(includes).to_a

    # Figure out latest parsed submissions using all submissions
    latest_submissions = {}
    submissions.each do |sub|
      next if include_ready && !sub.ready?
      latest_submissions[sub.ontology.acronym] ||= sub
      otherId = latest_submissions[sub.ontology.acronym].submissionId
      if sub.submissionId > otherId
        latest_submissions[sub.ontology.acronym] = sub
      end
    end
    return latest_submissions
  end

  def self.mapping_counts(enable_debug=false,logger=nil,reload_cache=false)
    if not enable_debug
      logger = nil
    end
    t = Time.now
    latest = retrieve_latest_submissions()
    counts = {}
    # Counting for External mappings
    t0 = Time.now
    external_uri = LinkedData::Models::ExternalClass.graph_uri
    exter_counts = mapping_ontologies_count(external_uri,nil,reload_cache=reload_cache)
    exter_total = 0
    exter_counts.each do |k,v|
      exter_total += v
    end
    counts[external_uri.to_s] = exter_total
    if enable_debug
      logger.info("Time for External Mappings took #{Time.now - t0} sec. records #{exter_total}")
    end
    LinkedData.settings.interportal_hash ||= {}
    # Counting for Interportal mappings
    LinkedData.settings.interportal_hash.each_key do |acro|
      t0 = Time.now
      interportal_uri = LinkedData::Models::InterportalClass.graph_uri(acro)
      inter_counts = mapping_ontologies_count(interportal_uri,nil,reload_cache=reload_cache)
      inter_total = 0
      inter_counts.each do |k,v|
        inter_total += v
      end
      counts[interportal_uri.to_s] = inter_total
      if enable_debug
        logger.info("Time for #{interportal_uri.to_s} took #{Time.now - t0} sec. records #{inter_total}")
      end
    end
    # Counting for mappings between the ontologies hosted by the BioPortal appliance
    i = 0
    latest.each do |acro,sub|
      t0 = Time.now
      s_counts = mapping_ontologies_count(sub,nil,reload_cache=reload_cache)
      s_total = 0
      s_counts.each do |k,v|
        s_total += v
      end
      counts[acro] = s_total
      i += 1
      if enable_debug
        logger.info("#{i}/#{latest.count} " +
            "Time for #{acro} took #{Time.now - t0} sec. records #{s_total}")
        logger.flush
      end
      sleep(5)
    end
    if enable_debug
      logger.info("Total time #{Time.now - t} sec.")
      logger.flush
    end
    return counts
  end

  def self.mapping_ontologies_count(sub1,sub2,reload_cache=false)
    if sub1.instance_of?(LinkedData::Models::OntologySubmission)
      sub1 = sub1.id
    else
      sub1 = sub1
    end
    template = <<-eos
{
  GRAPH <#{sub1.to_s}> {
      ?s1 <predicate> ?o .
  }
  GRAPH graph {
      ?s2 <predicate> ?o .
  }
}
eos
    group_count = nil
    count = 0
    if sub2.nil?
      group_count = {}
    end
    mapping_predicates().each do |_source,mapping_predicate|
      block = template.gsub("predicate", mapping_predicate[0])
      if sub2.nil?
      else
      end
      query_template = <<-eos
      SELECT variables
      WHERE {
      block
      filter
      } group
eos
      query = query_template.sub("block", block)
      filter = ""
      if _source != "SAME_URI"
        filter += "FILTER (?s1 != ?s2)"
      end
      if sub2.nil?
        if sub1.to_s != LinkedData::Models::ExternalClass.graph_uri.to_s
          ont_id = sub1.to_s.split("/")[0..-3].join("/")
          #STRSTARTS is used to not count older graphs
          filter += "\nFILTER (!STRSTARTS(str(?g),'#{ont_id}'))"
        end
        query = query.sub("graph","?g")
        query = query.sub("filter",filter)
        query = query.sub("variables","?g (count(?s1) as ?c)")
        query = query.sub("group","GROUP BY ?g")
      else
        query = query.sub("graph","<#{sub2.id.to_s}>")
        query = query.sub("filter",filter)
        query = query.sub("variables","(count(?s1) as ?c)")
        query = query.sub("group","")
      end
      epr = Goo.sparql_query_client(:main)
      graphs = [sub1, LinkedData::Models::MappingProcess.type_uri]
      unless sub2.nil?
        graphs << sub2.id
      end
      solutions = nil
      if sub2.nil?
        solutions = epr.query(query,
                              graphs: graphs, reload_cache: reload_cache)
        solutions.each do |sol|
          graph2 = sol[:g].to_s
          acr = ""
          if graph2.start_with?(LinkedData::Models::InterportalClass.graph_base_str) || graph2 == LinkedData::Models::ExternalClass.graph_uri.to_s
            acr = graph2
          else
            acr = graph2.to_s.split("/")[-3]
          end
          if group_count[acr].nil?
            group_count[acr] = 0
          end
          group_count[acr] += sol[:c].object
        end
      else
        solutions = epr.query(query,
                              graphs: graphs )
        solutions.each do |sol|
          count += sol[:c].object
        end
      end
    end #per predicate query

    if sub2.nil?
      return group_count
    end
    return count
  end

  def self.empty_page(page,size)
      p = Goo::Base::Page.new(page,size,nil,[])
      p.aggregate = 0
      return p
  end

  def self.mappings_ontologies(sub1,sub2,page,size,classId=nil,reload_cache=false)
    if sub1.respond_to?(:id)
      # Case where sub1 is a Submission
      sub1 = sub1.id
      acr1 = sub1.to_s.split("/")[-3]
    else
      acr1 = sub1.to_s
    end
    if sub2.nil?
      acr2 = nil
    elsif sub2.respond_to?(:id)
      # Case where sub2 is a Submission
      sub2 = sub2.id
      acr2 = sub2.to_s.split("/")[-3]
    else
      acr2 = sub2.to_s
    end

    union_template = <<-eos
{
  GRAPH <#{sub1.to_s}> {
      classId <predicate> ?o .
  }
  GRAPH graph {
      ?s2 <predicate> ?o .
  }
  bind
}
eos
    blocks = []
    mappings = []
    persistent_count = 0
    if classId.nil?
      pcount = LinkedData::Models::MappingCount.where(
          ontologies: acr1
      )
      if not acr2 == nil
        pcount = pcount.and(ontologies: acr2)
      end
      f = Goo::Filter.new(:pair_count) == (not acr2.nil?)
      pcount = pcount.filter(f)
      pcount = pcount.include(:count)
      pcount = pcount.all
      if pcount.length == 0
        persistent_count = 0
      else
        persistent_count = pcount.first.count
      end
      if persistent_count == 0
        return LinkedData::Mappings.empty_page(page,size)
      end
    end

    if classId.nil?
      union_template = union_template.sub("classId", "?s1")
    else
      union_template = union_template.sub("classId", "<#{classId.to_s}>")
    end

    mapping_predicates().each do |_source,mapping_predicate|
      union_block = union_template.gsub("predicate", mapping_predicate[0])
      union_block = union_block.sub("bind","BIND ('#{_source}' AS ?source)")
      if sub2.nil?
        union_block = union_block.sub("graph","?g")
      else
        union_block = union_block.sub("graph","<#{sub2.to_s}>")
      end
      blocks << union_block
    end
    unions = blocks.join("\nUNION\n")

    mappings_in_ontology = <<-eos
SELECT DISTINCT variables
WHERE {
unions
filter
} page_group
eos
    query = mappings_in_ontology.sub( "unions", unions)
    variables = "?s2 graph ?source ?o"
    if classId.nil?
      variables = "?s1 " + variables
    end
    query = query.sub("variables", variables)
    filter = ""
    if classId.nil?
      filter = "FILTER ((?s1 != ?s2) || (?source = 'SAME_URI'))"
    else
      filter = ""
    end
    if sub2.nil?
      query = query.sub("graph","?g")
      ont_id = sub1.to_s.split("/")[0..-3].join("/")
      #STRSTARTS is used to not count older graphs
      #no need since now we delete older graphs
      filter += "\nFILTER (!STRSTARTS(str(?g),'#{ont_id}'))"
      query = query.sub("filter",filter)
    else
      query = query.sub("graph","")
      query = query.sub("filter",filter)
    end
    if size > 0
      pagination = "OFFSET offset LIMIT limit"
      query = query.sub("page_group",pagination)
      limit = size
      offset = (page-1) * size
      query = query.sub("limit", "#{limit}").sub("offset", "#{offset}")
    else
      query = query.sub("page_group","")
    end
    epr = Goo.sparql_query_client(:main)
    graphs = [sub1]
    unless sub2.nil?
      graphs << sub2
    end
    solutions = epr.query(query,
                          graphs: graphs, reload_cache: reload_cache)
    s1 = nil
    unless classId.nil?
      s1 = RDF::URI.new(classId.to_s)
    end
    solutions.each do |sol|
      graph2 = nil
      if sub2.nil?
        graph2 = sol[:g]
      else
        graph2 = sub2
      end
      if classId.nil?
        s1 = sol[:s1]
      end

      backup_mapping = nil
      mapping = nil
      if sol[:source].to_s == "REST"
        backup_mapping = LinkedData::Models::RestBackupMapping
                      .find(sol[:o]).include(:process, :class_urns).first
        backup_mapping.process.bring_remaining
      end

      classes = get_mapping_classes(s1.to_s, sub1.to_s, sol[:s2].to_s, graph2, backup_mapping)

      if backup_mapping.nil?
        mapping = LinkedData::Models::Mapping.new(
                    classes,sol[:source].to_s)
      else
        mapping = LinkedData::Models::Mapping.new(
                    classes,sol[:source].to_s,
                    backup_mapping.process,backup_mapping.id)
      end
      mappings << mapping
    end
    if size == 0
      return mappings
    end
    page = Goo::Base::Page.new(page,size,nil,mappings)
    page.aggregate = persistent_count
    return page
  end

  def self.mappings_ontology(sub,page,size,classId=nil,reload_cache=false)
    return self.mappings_ontologies(sub,nil,page,size,classId=classId,
                                    reload_cache=reload_cache)
  end

  def self.read_only_class(classId,submissionId)
      ontologyId = submissionId
      acronym = nil
      unless submissionId["submissions"].nil?
        ontologyId = submissionId.split("/")[0..-3]
        acronym = ontologyId.last
        ontologyId = ontologyId.join("/")
      else
        acronym = ontologyId.split("/")[-1]
      end
      ontology = LinkedData::Models::Ontology
            .read_only(
              id: RDF::IRI.new(ontologyId),
              acronym: acronym)
      submission = LinkedData::Models::OntologySubmission
            .read_only(
              id: RDF::IRI.new(ontologyId+"/submissions/latest"),
              ontology: ontology)
      mappedClass = LinkedData::Models::Class
            .read_only(
              id: RDF::IRI.new(classId),
              submission: submission,
              urn_id: LinkedData::Models::Class.urn_id(acronym,classId) )
      return mappedClass
  end

  def self.migrate_rest_mappings(acronym)
    mappings = LinkedData::Models::RestBackupMapping
                .where.include(:uuid, :class_urns, :process).all
    if mappings.length == 0
      return []
    end
    triples = []

    rest_predicate = mapping_predicates()["REST"][0]
    mappings.each do |m|
      m.class_urns.each do |u|
        u = u.to_s
        if u.start_with?("urn:#{acronym}")
          class_id = u.split(":")[2..-1].join(":")
          triples <<
            " <#{class_id}> <#{rest_predicate}> <#{m.id}> . "
        end
      end
    end
    return triples

  end

  def self.delete_rest_mapping(mapping_id)
    mapping = get_rest_mapping(mapping_id)
    if mapping.nil?
      return nil
    end
    rest_predicate = mapping_predicates()["REST"][0]
    classes = mapping.classes
    classes.each do |c|
      if c.respond_to?(:submission)
        sub = c.submission
        unless sub.id.to_s["latest"].nil?
          #the submission in the class might point to latest
          sub = LinkedData::Models::Ontology.find(c.submission.ontology.id)
                    .first
                    .latest_submission
        end
        del_from_graph = sub.id
      elsif c.respond_to?(:source)
        # If it is an InterportalClass
        del_from_graph = LinkedData::Models::InterportalClass.graph_uri(c.source)
      else
        # If it is an ExternalClass
        del_from_graph = LinkedData::Models::ExternalClass.graph_uri
      end
      graph_delete = RDF::Graph.new
      graph_delete << [c.id, RDF::URI.new(rest_predicate), mapping.id]
      Goo.sparql_update_client.delete_data(graph_delete, graph: del_from_graph)
    end
    mapping.process.delete
    backup = LinkedData::Models::RestBackupMapping.find(mapping_id).first
    unless backup.nil?
      backup.delete
    end
    return mapping
  end

  # A function only used in ncbo_cron. To make sure all triples that link mappings to class are well deleted (use of metadata/def/mappingRest predicate)
  def self.delete_all_rest_mappings_from_sparql
    rest_predicate = mapping_predicates()["REST"][0]
    actual_graph = ""
    count = 0
    qmappings = <<-eos
SELECT DISTINCT ?g ?class_uri ?backup_mapping
WHERE {
  GRAPH ?g {
    ?class_uri <#{rest_predicate}> ?backup_mapping .
  }
}
    eos
    epr = Goo.sparql_query_client(:main)
    epr.query(qmappings).each do |sol|
      if actual_graph == sol[:g].to_s && count < 4000
        # Trying to delete more than 4995 triples at the same time cause a memory error. So 4000 by 4000. Or until we met a new graph
        graph_delete << [RDF::URI.new(sol[:class_uri].to_s), RDF::URI.new(rest_predicate), RDF::URI.new(sol[:backup_mapping].to_s)]
      else
        if count == 0
          graph_delete = RDF::Graph.new
          graph_delete << [RDF::URI.new(sol[:class_uri].to_s), RDF::URI.new(rest_predicate), RDF::URI.new(sol[:backup_mapping].to_s)]
        else
          Goo.sparql_update_client.delete_data(graph_delete, graph: RDF::URI.new(actual_graph))
          graph_delete = RDF::Graph.new
          graph_delete << [RDF::URI.new(sol[:class_uri].to_s), RDF::URI.new(rest_predicate), RDF::URI.new(sol[:backup_mapping].to_s)]
        end
        count = 0
        actual_graph = sol[:g].to_s
      end
      count = count + 1
    end
    if count > 0
      Goo.sparql_update_client.delete_data(graph_delete, graph: RDF::URI.new(actual_graph))
    end
  end


  # A method that generate classes depending on the nature of the mapping : Internal, External or Interportal
  def self.get_mapping_classes(c1, g1, c2, g2, backup)
    external_source = nil
    external_ontology = nil
    # Generate classes if g1 is interportal or external
    if g1.start_with?(LinkedData::Models::InterportalClass.graph_base_str)
      backup.class_urns.each do |class_urn|
        # get source and ontology from the backup URI from 4store (source(like urn):ontology(like STY):class)
        if !class_urn.start_with?("urn:")
          external_source = class_urn.split(":")[0]
          external_ontology = class_urn.split(":")[1]
        end
      end
      classes = [ LinkedData::Models::InterportalClass.new(c1, external_ontology, external_source),
                  read_only_class(c2,g2)]
    elsif g1 == LinkedData::Models::ExternalClass.graph_uri.to_s
      backup.class_urns.each do |class_urn|
        if !class_urn.start_with?("urn:")
          external_ontology = class_urn.split(":")[1]
        end
      end
      classes = [ LinkedData::Models::ExternalClass.new(c1, external_ontology),
                  read_only_class(c2,g2)]

    # Generate classes if g2 is interportal or external
    elsif g2.start_with?(LinkedData::Models::InterportalClass.graph_base_str)
      backup.class_urns.each do |class_urn|
        if !class_urn.start_with?("urn:")
          external_source = class_urn.split(":")[0]
          external_ontology = class_urn.split(":")[1]
        end
      end
      classes = [ read_only_class(c1,g1),
                  LinkedData::Models::InterportalClass.new(c2, external_ontology, external_source)]
    elsif g2 == LinkedData::Models::ExternalClass.graph_uri.to_s
      backup.class_urns.each do |class_urn|
        if !class_urn.start_with?("urn:")
          external_ontology = class_urn.split(":")[1]
        end
      end
      classes = [ read_only_class(c1,g1),
                  LinkedData::Models::ExternalClass.new(c2, external_ontology)]

    else
      classes = [ read_only_class(c1,g1),
                  read_only_class(c2,g2) ]
    end

    return classes
  end

  def self.get_rest_mapping(mapping_id)
    backup = LinkedData::Models::RestBackupMapping.find(mapping_id).include(:class_urns).first
    if backup.nil?
      return nil
    end
    rest_predicate = mapping_predicates()["REST"][0]
    qmappings = <<-eos
SELECT DISTINCT ?s1 ?c1 ?s2 ?c2 ?uuid ?o
WHERE {
  ?uuid <http://data.bioontology.org/metadata/process> ?o .

  GRAPH ?s1 {
    ?c1 <#{rest_predicate}> ?uuid .
  }
  GRAPH ?s2 {
    ?c2 <#{rest_predicate}> ?uuid .
  }
FILTER(?uuid = <#{mapping_id}>)
FILTER(?s1 != ?s2)
} LIMIT 1
eos
    epr = Goo.sparql_query_client(:main)
    graphs = [LinkedData::Models::MappingProcess.type_uri]
    mapping = nil
    epr.query(qmappings,
              graphs: graphs).each do |sol|
      classes = get_mapping_classes(sol[:c1].to_s, sol[:s1].to_s, sol[:c2].to_s, sol[:s2].to_s, backup)
      process = LinkedData::Models::MappingProcess.find(sol[:o]).first
      mapping = LinkedData::Models::Mapping.new(classes,"REST",
                                                process,
                                                sol[:uuid])
    end
    return mapping
  end

  def self.generate_class_urns(classes)
    class_urns = []
    classes.each do |c|
      if c.instance_of?LinkedData::Models::Class
        acronym = c.submission.id.to_s.split("/")[-3]
        class_urns << RDF::URI.new(
            LinkedData::Models::Class.urn_id(acronym,c.id.to_s))
      else
        # Generate classes urns using the source (e.g.: ncbo or ext), the ontology acronym and the class id
        class_urns << RDF::URI.new("#{c[:source]}:#{c[:ontology]}:#{c[:id]}")
      end
    end
    return class_urns
  end

  def self.check_mapping_exist(cls, relations_array)
    class_urns = generate_class_urns(cls)
    mapping_exist = false
    qmappings = <<-eos
SELECT DISTINCT ?uuid ?urn1 ?urn2 ?p
WHERE {
  ?uuid <http://data.bioontology.org/metadata/class_urns> ?urn1 .
  ?uuid <http://data.bioontology.org/metadata/class_urns> ?urn2 .
  ?uuid <http://data.bioontology.org/metadata/process> ?p .
FILTER(?urn1 = <#{class_urns[0]}>)
FILTER(?urn2 = <#{class_urns[1]}>)
} LIMIT 10
    eos
    epr = Goo.sparql_query_client(:main)
    graphs = [LinkedData::Models::MappingProcess.type_uri]
    epr.query(qmappings,
              graphs: graphs).each do |sol|
      process = LinkedData::Models::MappingProcess.find(sol[:p]).include(:relation).first
      process_relations = process.relation.map {|r| r.to_s}
      relations_array = relations_array.map {|r| r.to_s}
      if process_relations.sort == relations_array.sort
        mapping_exist = true
        break
      end
    end
    return mapping_exist
  end

  # A method to easily add a new mapping without using ontologies_api
  # Where "params" is the mapping hash (containing classes, relation, creator and comment)
  # Note: there is no interportal class validation and no check if mapping already exist
  def self.bulk_load_mapping(params, check_exist=true, logger=nil)
    raise ArgumentError, "Input does not contain classes" if !params[:classes]
    if params[:classes].length > 2
      raise ArgumentError, "Input does not contain at least 2 terms"
    end
    raise ArgumentError, "Input does not contain mapping relation" if !params[:relation]
    if params[:relation].kind_of?(Array)
      raise ArgumentError, "Input contains too many mapping relations (max 5)" if params[:relation].length > 5
      params[:relation].each do |relation|
        begin
          URI(relation)
        rescue URI::InvalidURIError => e
          raise ArgumentError, "#{relation} is not a valid URI for relations."
        end
      end
    end
    raise ArgumentError, "Input does not contain user creator ID" if !params[:creator]
    classes = []
    LinkedData.settings.interportal_hash ||= {}
    mapping_process_name = "REST Mapping"
    params[:classes].each do |class_id,ontology_id|
      interportal_prefix = ontology_id.split(":")[0]
      if ontology_id.start_with? "ext:"
        #TODO: check if the ontology is a well formed URI
        # Just keep the source and the class URI if the mapping is external or interportal and change the mapping process name
        raise ArgumentError, "Impossible to map 2 classes outside of BioPortal" if mapping_process_name != "REST Mapping"
        mapping_process_name = "External Mapping"
        ontology_uri = ontology_id.sub("ext:", "")
        if !uri?(ontology_uri)
          raise ArgumentError, "Ontology URI '#{ontology_uri.to_s}' is not valid"
        end
        if !uri?(class_id)
          raise ArgumentError, "Class URI '#{class_id.to_s}' is not valid"
        end
        ontology_uri = CGI.escape(ontology_uri)
        c = {:source => "ext", :ontology => ontology_uri, :id => class_id}
        classes << c
      elsif LinkedData.settings.interportal_hash.has_key?(interportal_prefix)
        #Check if the prefix is contained in the interportal hash to create a mapping to this bioportal
        raise ArgumentError, "Impossible to map 2 classes outside of BioPortal" if mapping_process_name != "REST Mapping"
        mapping_process_name = "Interportal Mapping #{interportal_prefix}"
        ontology_acronym = ontology_id.sub("#{interportal_prefix}:", "")
        c = {:source => interportal_prefix, :ontology => ontology_acronym, :id => class_id}
        classes << c
      else
        o = ontology_id
        o = LinkedData::Models::Ontology.find(o)
                .include(submissions:
                             [:submissionId, :submissionStatus]).first
        if o.nil?
          raise ArgumentError, "Ontology with ID `#{ontology_id}` not found"
        end
        submission = o.latest_submission
        if submission.nil?
          raise ArgumentError, "Ontology with id #{ontology_id} does not have parsed valid submission"
        end
        submission.bring(ontology: [:acronym])
        c = LinkedData::Models::Class.find(RDF::URI.new(class_id))
                .in(submission)
                .first
        if c.nil?
          raise ArgumentError, "Class ID `#{class_id}` not found in `#{submission.id.to_s}`"
        end
        classes << c
      end
    end
    user_id = params[:creator].start_with?("http://") ?
        params[:creator].split("/")[-1] : params[:creator]
    user_creator = LinkedData::Models::User.find(user_id)
                       .include(:username).first
    if user_creator.nil?
      raise ArgumentError, "User with id `#{params[:creator]}` not found"
    end
    process = LinkedData::Models::MappingProcess.new(
        :creator => user_creator, :name => mapping_process_name)
    relations_array = []
    if !params[:relation].kind_of?(Array)
      relations_array.push(RDF::URI.new(params[:relation]))
    else
      params[:relation].each do |relation|
        relations_array.push(RDF::URI.new(relation))
      end
    end
    # Check if the mapping exist (check mapping by default)
    raise ArgumentError, "Mapping already exists" if LinkedData::Mappings.check_mapping_exist(classes, relations_array) if check_exist
    process.relation = relations_array
    process.date = DateTime.now
    process_fields = [:source,:source_name, :comment]
    process_fields.each do |att|
      process.send("#{att}=",params[att]) if params[att]
    end
    process.save
    begin
      mapping = LinkedData::Mappings.create_rest_mapping(classes,process)
    rescue => e
      # Remove the created process if the following steps of the mapping fail
      process.delete
      raise IOError, "Loading mapping has failed. Message: #{e.message.to_s}"
    end

    return mapping
  end

  def self.create_rest_mapping(classes,process)
    unless process.instance_of? LinkedData::Models::MappingProcess
      raise ArgumentError, "Process should be instance of MappingProcess"
    end
    if classes.length != 2
      raise ArgumentError, "Create REST is avalaible for two classes. " +
                           "Request contains #{classes.length} classes."
    end
    #first create back up mapping that lives across submissions
    LinkedData.settings.interportal_hash ||= {}
    begin
      backup_mapping = LinkedData::Models::RestBackupMapping.new
      backup_mapping.uuid = UUID.new.generate
      backup_mapping.process = process
      class_urns = generate_class_urns(classes)
      backup_mapping.class_urns = class_urns
      # Insert backup into 4store
      backup_mapping.save
    rescue => e
      raise IOError, "Saving backup mapping has failed. Message: #{e.message.to_s}"
    end

    #second add the mapping id to current submission graphs
    rest_predicate = mapping_predicates()["REST"][0]
    begin
      classes.each do |c|
        if c.instance_of?LinkedData::Models::Class
          sub = c.submission
          unless sub.id.to_s["latest"].nil?
            #the submission in the class might point to latest
            sub = LinkedData::Models::Ontology.find(c.submission.ontology.id)
                      .first
                      .latest_submission
          end
          c_id = c.id
          graph_id = sub.id
        else
          if LinkedData.settings.interportal_hash.has_key?(c[:source])
            # If it is a mapping from another Bioportal
            c_id = RDF::URI.new(c[:id])
            graph_id = LinkedData::Models::InterportalClass.graph_uri(c[:source])
          else
            # If it is an external mapping
            c_id = RDF::URI.new(c[:id])
            graph_id = LinkedData::Models::ExternalClass.graph_uri
          end
        end
        graph_insert = RDF::Graph.new
        graph_insert << [c_id, RDF::URI.new(rest_predicate), backup_mapping.id]
        Goo.sparql_update_client.insert_data(graph_insert, graph: graph_id)
      end
    rescue => e
      # Remove the created backup if the following steps of the mapping fail
      backup_mapping.delete
      raise IOError, "Inserting the mapping ID in the submission graphs has failed. Message: #{e.message.to_s}"
    end

    mapping = LinkedData::Models::Mapping.new(classes,"REST",process)

    return mapping
  end

  def self.mappings_for_classids(class_ids,sources=["REST","CUI"])
    class_ids = class_ids.uniq
    predicates = {}
    sources.each do |t|
      predicates[mapping_predicates()[t][0]] = t
    end
    qmappings = <<-eos
SELECT DISTINCT ?s1 ?c1 ?s2 ?c2 ?pred
WHERE {
  GRAPH ?s1 {
    ?c1 ?pred ?o .
  }
  GRAPH ?s2 {
    ?c2 ?pred ?o .
  }
FILTER(?s1 != ?s2)
FILTER(filter_pred)
FILTER(filter_classes)
}
eos
    qmappings = qmappings.gsub("filter_pred",
                    predicates.keys.map { |x| "?pred = <#{x}>"}.join(" || "))
    qmappings = qmappings.gsub("filter_classes",
                      class_ids.map { |x| "?c1 = <#{x}>" }.join(" || "))
    epr = Goo.sparql_query_client(:main)
    graphs = [LinkedData::Models::MappingProcess.type_uri]
    mappings = []
    epr.query(qmappings,
              graphs: graphs).each do |sol|
      classes = [ read_only_class(sol[:c1].to_s,sol[:s1].to_s),
                read_only_class(sol[:c2].to_s,sol[:s2].to_s) ]
      source = predicates[sol[:pred].to_s]
      mappings << LinkedData::Models::Mapping.new(classes,source)
    end
    return mappings
  end

  def self.recent_rest_mappings(n)
    graphs = [LinkedData::Models::MappingProcess.type_uri]
    qdate = <<-eos
SELECT DISTINCT ?s
FROM <#{LinkedData::Models::MappingProcess.type_uri}>
WHERE { ?s <http://data.bioontology.org/metadata/date> ?o }
ORDER BY DESC(?o) LIMIT #{n}
eos
    epr = Goo.sparql_query_client(:main)
    procs = []
    epr.query(qdate, graphs: graphs,query_options: {rules: :NONE}).each do |sol|
      procs << sol[:s]
    end
    if procs.length == 0
      return []
    end
    graphs = [LinkedData::Models::MappingProcess.type_uri]
    proc_object = Hash.new
    LinkedData::Models::MappingProcess.where
        .include(LinkedData::Models::MappingProcess.attributes)
        .all.each do |obj|
          #highly cached query
          proc_object[obj.id.to_s] = obj
    end
    procs = procs.map { |x| "?o = #{x.to_ntriples}" }.join " || "
    rest_predicate = mapping_predicates()["REST"][0]
    qmappings = <<-eos
SELECT DISTINCT ?ont1 ?c1 ?s1 ?ont2 ?c2 ?s2 ?o ?uuid
WHERE {
  ?uuid <http://data.bioontology.org/metadata/process> ?o .

  OPTIONAL { ?s1 <http://data.bioontology.org/metadata/ontology> ?ont1 . }
  GRAPH ?s1 {
    ?c1 <#{rest_predicate}> ?uuid .
  }
  OPTIONAL { ?s2 <http://data.bioontology.org/metadata/ontology> ?ont2 . }
  GRAPH ?s2 {
    ?c2 <#{rest_predicate}> ?uuid .
  }
FILTER(?ont1 != ?ont2)
FILTER(?c1 != ?c2)
FILTER (#{procs})
}
eos
    epr = Goo.sparql_query_client(:main)
    mappings = []
    epr.query(qmappings,
              graphs: graphs,query_options: {rules: :NONE}).each do |sol|
      if sol[:ont1].nil?
        # if the 1st class is from External or Interportal we don't want it to be in the list of recent, it has to be in 2nd
        next
      else
        ont1 = sol[:ont1].to_s
      end
      if sol[:ont2].nil?
        ont2 = sol[:s2].to_s
      else
        ont2 = sol[:ont2].to_s
      end

      mapping_id = RDF::URI.new(sol[:uuid].to_s)
      backup = LinkedData::Models::RestBackupMapping.find(mapping_id).include(:class_urns).first
      classes = get_mapping_classes(sol[:c1].to_s, ont1, sol[:c2].to_s, ont2, backup)

      process = proc_object[sol[:o].to_s]
      mapping = LinkedData::Models::Mapping.new(classes,"REST",
                                                process,
                                                sol[:uuid])
      mappings << mapping
    end
    return mappings.sort_by { |x| x.process.date }.reverse[0..n-1]
  end

  def self.retrieve_latest_submissions(options = {})
    status = (options[:status] || "RDF").to_s.upcase
    include_ready = status.eql?("READY") ? true : false
    status = "RDF" if status.eql?("READY")
    any = true if status.eql?("ANY")
    include_views = options[:include_views] || false
    if any
      submissions_query = LinkedData::Models::OntologySubmission.where
    else
      submissions_query = LinkedData::Models::OntologySubmission
                            .where(submissionStatus: [ code: status])
    end

    submissions_query = submissions_query.filter(Goo::Filter.new(ontology: [:viewOf]).unbound) unless include_views
    submissions = submissions_query.
        include(:submissionStatus,:submissionId, ontology: [:acronym]).to_a

    latest_submissions = {}
    submissions.each do |sub|
      next if include_ready && !sub.ready?
      latest_submissions[sub.ontology.acronym] ||= sub
      latest_submissions[sub.ontology.acronym] = sub if sub.submissionId > latest_submissions[sub.ontology.acronym].submissionId
    end
    return latest_submissions
  end

  def self.create_mapping_counts(logger)
    # Create mapping counts for ontology alone
    new_counts = LinkedData::Mappings.mapping_counts(
                                        enable_debug=true,logger=logger,
                                        reload_cache=true)
    persistent_counts = {}
    f = Goo::Filter.new(:pair_count) == false
    LinkedData::Models::MappingCount.where.filter(f)
      .include(:ontologies,:count)
    .include(:all)
    .all
    .each do |m|
      persistent_counts[m.ontologies.first] = m
    end

    new_counts.each_key do |acr|
      new_count = new_counts[acr]
      if persistent_counts.include?(acr)
        inst = persistent_counts[acr]
        if new_count == 0
          inst.delete
        elsif new_count != inst.count
          inst.bring_remaining
          inst.count = new_count
          if not inst.valid? && logger
            logger.info("Error saving #{inst.id.to_s} #{inst.errors}")
          else
             inst.save
          end
        end
      else
        if new_count != 0
          m = LinkedData::Models::MappingCount.new
          m.ontologies = [acr]
          m.pair_count = false
          m.count = new_count
          if not m.valid? && logger
            logger.info("Error saving #{inst.id.to_s} #{inst.errors}")
          else
            m.save
          end
        end
      end
    end

    # Create mapping counts for pair ontologies
    retrieve_latest_submissions.each do |acr,sub|

      new_counts = LinkedData::Mappings
                .mapping_ontologies_count(sub,nil,reload_cache=true)
      persistent_counts = {}
      LinkedData::Models::MappingCount.where(pair_count: true)
                                             .and(ontologies: acr)
      .include(:ontologies,:count)
      .all
      .each do |m|
        other = m.ontologies.first
        if other == acr
          other = m.ontologies[1]
        end
        persistent_counts[other] = m
      end

      new_counts.each_key do |other|
        new_count = new_counts[other]
        if persistent_counts.include?(other)
          inst = persistent_counts[other]
          if new_count == 0
            inst.delete
          elsif new_count != inst.count
            inst.bring_remaining
            inst.count = new_count
            inst.save
          end
        else
          if new_count != 0
            m = LinkedData::Models::MappingCount.new
            m.count = new_count
            m.ontologies = [acr,other]
            m.pair_count = true
            m.save
          end
        end
      end

      # Remove persistent_counts that are not in new_counts (because no mappings anymore)
      persistent_counts.each_key do |count_key|
        if !new_counts.include?(count_key)
          inst = persistent_counts[count_key]
          inst.delete
        end
      end

    end
  end

end
end
