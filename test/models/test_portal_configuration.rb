require_relative '../test_case'

class TestPortalConfiguration < LinkedData::TestCase

  def test_read_portal_config
    config = LinkedData::Models::PortalConfig.current_portal_config

    expected = { acronym: 'bioportal',
                 title: 'NCBO BioPortal',
                 color: '#234979',
                 description: "The world's most comprehensive repository of biomedical ontologies",
                 logo: '',
                 fundedBy: [{ img_src: 'https://identity.stanford.edu/wp-content/uploads/sites/3/2020/07/block-s-right.png', url: 'https://www.stanford.edu' },
                            { img_src: 'https://ontoportal.org/images/logo.png', url: 'https://ontoportal.org/' }],
                 id: RDF::URI.new('http://data.bioontology.org/SemanticArtefactCatalogues/bioportal') }

    assert config.valid?

    assert_equal expected, config.to_hash

    expected_federated_portals = { 'agroportal' => { api: 'http://data.agroportal.lirmm.fr', ui: 'http://agroportal.lirmm.fr', apikey: '1cfae05f-9e67-486f-820b-b393dec5764b', color: '#1e2251' },
                                   'bioportal' => { api: 'http://data.bioontology.org', ui: 'http://bioportal.bioontology.org', apikey: '4a5011ea-75fa-4be6-8e89-f45c8c84844e', color: '#234979' } }.symbolize_keys
    assert_equal expected_federated_portals, config.federated_portals
    refute_nil config.numberOfArtefacts
  end
end

