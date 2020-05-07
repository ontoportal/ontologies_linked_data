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
    template = <<-eos
{
  GRAPH <#{sub1.id.to_s}> {
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
        ont_id = sub1.id.to_s.split("/")[0..-3].join("/")
        #STRSTARTS is used to not count older graphs
        filter += "\nFILTER (!STRSTARTS(str(?g),'#{ont_id}'))"
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
      graphs = [sub1.id, LinkedData::Models::MappingProcess.type_uri]
      unless sub2.nil?
        graphs << sub2.id
      end
      solutions = nil
      if sub2.nil?
        solutions = epr.query(query,
                              graphs: graphs, reload_cache: reload_cache)
        solutions.each do |sol|
          acr = sol[:g].to_s.split("/")[-3]
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
    union_template = <<-eos
{
  GRAPH <#{sub1.id.to_s}> {
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
    acr1 = sub1.id.to_s.split("/")[-3]
    if classId.nil?
      acr2 = nil

      if not sub2.nil?
        acr2 = sub2.id.to_s.split("/")[-3]
      end
      pcount = LinkedData::Models::MappingCount.where(ontologies: acr1)
      if not acr2 == nil
        pcount = pcount.and(ontologies: acr2)
      end
      f = Goo::Filter.new(:pair_count) == (not acr2.nil?)
      pcount = pcount.filter(f)
      pcount = pcount.include(:count)
      pcount_arr = pcount.all

      if pcount_arr.length == 0
        persistent_count = 0
      else
        persistent_count = pcount_arr.first.count
      end

      if persistent_count == 0
        return LinkedData::Mappings.empty_page(page,size)
      end
    end

    if classId.nil?
      union_template = union_template.gsub("classId", "?s1")
    else
      union_template = union_template.gsub("classId", "<#{classId.to_s}>")
    end

    mapping_predicates().each do |_source,mapping_predicate|
      union_block = union_template.gsub("predicate", mapping_predicate[0])
      union_block = union_block.gsub("bind","BIND ('#{_source}' AS ?source)")
      if sub2.nil?
        union_block = union_block.gsub("graph","?g")
      else
        union_block = union_block.gsub("graph","<#{sub2.id.to_s}>")
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
    query = mappings_in_ontology.gsub( "unions", unions)
    variables = "?s2 graph ?source ?o"
    if classId.nil?
      variables = "?s1 " + variables
    end
    query = query.gsub("variables", variables)
    filter = ""
    if classId.nil?
      filter = "FILTER ((?s1 != ?s2) || (?source = 'SAME_URI'))"
    else
      filter = ""
    end
    if sub2.nil?
      query = query.gsub("graph","?g")
      ont_id = sub1.id.to_s.split("/")[0..-3].join("/")
      #STRSTARTS is used to not count older graphs
      #no need since now we delete older graphs
      filter += "\nFILTER (!STRSTARTS(str(?g),'#{ont_id}'))"
      query = query.gsub("filter",filter)
    else
      query = query.gsub("graph","")
      query = query.gsub("filter",filter)
    end
    if size > 0
      pagination = "OFFSET offset LIMIT limit"
      query = query.gsub("page_group",pagination)
      limit = size
      offset = (page-1) * size
      query = query.gsub("limit", "#{limit}").gsub("offset", "#{offset}")
    else
      query = query.gsub("page_group","")
    end
    epr = Goo.sparql_query_client(:main)
    graphs = [sub1.id]
    unless sub2.nil?
      graphs << sub2.id
    end
    solutions = epr.query(query, graphs: graphs, reload_cache: reload_cache)
    s1 = nil
    unless classId.nil?
      s1 = RDF::URI.new(classId.to_s)
    end
    solutions.each do |sol|
      graph2 = nil
      if sub2.nil?
        graph2 = sol[:g]
      else
        graph2 = sub2.id
      end
      if classId.nil?
        s1 = sol[:s1]
      end
      classes = [ read_only_class(s1.to_s,sub1.id.to_s),
                read_only_class(sol[:s2].to_s,graph2.to_s) ]

      backup_mapping = nil
      mapping = nil
      if sol[:source].to_s == "REST"
        backup_mapping = LinkedData::Models::RestBackupMapping
                      .find(sol[:o]).include(:process).first
        backup_mapping.process.bring_remaining
      end
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
      sub = c.submission
      unless sub.id.to_s["latest"].nil?
        #the submission in the class might point to latest
        sub = LinkedData::Models::Ontology.find(c.submission.ontology.id)
                .first
                .latest_submission
      end
      graph_delete = RDF::Graph.new
      graph_delete << [c.id, RDF::URI.new(rest_predicate), mapping.id]
      Goo.sparql_update_client.delete_data(graph_delete, graph: sub.id)
    end
    mapping.process.delete
    backup = LinkedData::Models::RestBackupMapping.find(mapping_id).first
    unless backup.nil?
      backup.delete
    end
    return mapping
  end

  def self.get_rest_mapping(mapping_id)
    backup = LinkedData::Models::RestBackupMapping.find(mapping_id).first
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
      classes = [ read_only_class(sol[:c1].to_s,sol[:s1].to_s),
                read_only_class(sol[:c2].to_s,sol[:s2].to_s) ]
      process = LinkedData::Models::MappingProcess.find(sol[:o]).first
      mapping = LinkedData::Models::Mapping.new(classes,"REST",
                                                process,
                                                sol[:uuid])
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
    backup_mapping = LinkedData::Models::RestBackupMapping.new
    backup_mapping.uuid = UUID.new.generate
    backup_mapping.process = process
    class_urns = []
    classes.each do |c|
      if c.instance_of?LinkedData::Models::Class
        acronym = c.submission.id.to_s.split("/")[-3]
        class_urns << RDF::URI.new(
          LinkedData::Models::Class.urn_id(acronym,c.id.to_s))

      else
        class_urns << RDF::URI.new(c.urn_id())
      end
    end
    backup_mapping.class_urns = class_urns
    backup_mapping.save

    #second add the mapping id to current submission graphs
    rest_predicate = mapping_predicates()["REST"][0]
    classes.each do |c|
      sub = c.submission
      unless sub.id.to_s["latest"].nil?
        #the submission in the class might point to latest
        sub = LinkedData::Models::Ontology.find(c.submission.ontology.id).first.latest_submission
      end
      graph_insert = RDF::Graph.new
      graph_insert << [c.id, RDF::URI.new(rest_predicate), backup_mapping.id]
      Goo.sparql_update_client.insert_data(graph_insert, graph: sub.id)
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
SELECT DISTINCT ?ont1 ?c1 ?ont2 ?c2 ?o ?uuid
WHERE {
  ?uuid <http://data.bioontology.org/metadata/process> ?o .

  ?s1 <http://data.bioontology.org/metadata/ontology> ?ont1 .
  GRAPH ?s1 {
    ?c1 <#{rest_predicate}> ?uuid .
  }
  ?s2 <http://data.bioontology.org/metadata/ontology> ?ont2 .
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
      classes = [ read_only_class(sol[:c1].to_s,sol[:ont1].to_s),
                read_only_class(sol[:c2].to_s,sol[:ont2].to_s) ]
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
        if new_count != inst.count
          inst.bring_remaining
          inst.count = new_count
          if not inst.valid? && logger
            logger.info("Error saving #{inst.id.to_s} #{inst.errors}")
          else
             inst.save
          end
        end
      else
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
          if new_count != inst.count
            inst.bring_remaining
            inst.count = new_count
            inst.save
          end
        else
          m = LinkedData::Models::MappingCount.new
          m.count = new_count
          m.ontologies = [acr,other]
          m.pair_count = true
          m.save
        end
      end
    end
  end

end
end
