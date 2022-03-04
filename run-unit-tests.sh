#!/bin/bash
# sample script to run unit tests with docker

#generate solr configsets
test/solr/generate_ncbo_configsets.sh

# build docker env
docker-compose build
# start up all containers and exit with exit code from unit-test container which runs unit tests
docker-compose up --exit-code-from unit-test
#docker-compose run --rm ont_ld bundle exec rake test TESTOPTS='-v'
