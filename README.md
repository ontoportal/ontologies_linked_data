ontologies_linked_data
======================

Unit test status:
 - master branch:   [![Build Status](https://bmir-jenkins.stanford.edu/buildStatus/icon?job=NCBO_OntLD_MasterTest)](https://bmir-jenkins.stanford.edu/job/NCBO_OntLD_MasterTest/)
 - staging branch:  [![Build Status](https://bmir-jenkins.stanford.edu/buildStatus/icon?job=NCBO_OntLD_StagingTest)](https://bmir-jenkins.stanford.edu/job/NCBO_OntLD_StagingTest/)

Models and serializers for ontologies and related artifacts backed by 4store

This is a component of the NCBO [ontologies_api](https://github.com/ncbo/ontologies_api).


## Add a new namespace in GOO for properties

To add new namespaces used in the `Goo.vocabulary` go to `lib/ontologies_linked_data/config/config.rb`

And use the GOO `add_namespace` method. For example:

```ruby
Goo.configure do |conf|
  conf.add_namespace(:omv, RDF::Vocabulary.new("http://omv.ontoware.org/2005/05/ontology#"))
end
```

* To iterate other the namespaces
```ruby
Goo.namespaces.each do |prefix,uri|
  puts "#{prefix}: #{uri}"
end
```

* To resolve a namespace
```ruby
Goo.vocabulary(:omv).to_s
```
