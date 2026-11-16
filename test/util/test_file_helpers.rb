require 'minitest/autorun'
require_relative '../../lib/ontologies_linked_data/utils/file'

class TestFileHelpers < Minitest::Test
  FILES = './test/data/ontology_files'.freeze
  HELPERS = LinkedData::Utils::FileHelpers

  def setup
    @src = Dir.mktmpdir('unzip-src-')
    @dst = Dir.mktmpdir('unzip-dst-')
  end

  def teardown
    FileUtils.remove_entry_secure(@src)
    FileUtils.remove_entry_secure(@dst)
  end

  def test_automaster_from_zip
    zipfile = "#{FILES}/SDO.zip"
    assert HELPERS.automaster?(zipfile, '.owl')
    assert_equal 'SDO.owl', HELPERS.automaster(zipfile, '.owl')

    zipfile = "#{FILES}/evoc_v2.9.zip"
    refute HELPERS.automaster?(zipfile, '.obo')
    assert_nil HELPERS.automaster(zipfile, '.obo')
  end

  def test_archive_detection
    file = "#{FILES}/BRO_v3.2.owl"
    gzipfile = write_gz('BRO_v3.2.owl.gz', File.read(file), orig_name: 'BRO_v3.2.owl')
    zipfile = "#{FILES}/evoc_v2.9.zip"
    tarfile = "#{FILES}/pizza.owl.tar"
    tgzfile = "#{FILES}/pizza.owl.tgz"
    missing = "#{FILES}/missing.zip"

    assert HELPERS.gzip?(gzipfile)
    refute HELPERS.gzip?(zipfile)
    refute HELPERS.gzip?(tarfile)
    refute HELPERS.gzip?(tgzfile)
    refute HELPERS.gzip?(file)
    refute HELPERS.gzip?(missing)

    refute HELPERS.zip?(gzipfile)
    assert HELPERS.zip?(zipfile)
    refute HELPERS.zip?(tarfile)
    refute HELPERS.zip?(tgzfile)
    refute HELPERS.zip?(file)
    refute HELPERS.zip?(missing)
  end

  def test_tar_is_unsupported
    assert_raises(StandardError) { HELPERS.filenames_in_archive("#{FILES}/pizza.owl.tar") }
    assert_raises(StandardError) { HELPERS.filenames_in_archive("#{FILES}/pizza.owl.tgz") }
  end

  def test_unzip_nested_entry
    zip_path = write_zip('ok.zip', 'dir/subdir/file.txt' => 'hello')

    extracted = HELPERS.unzip(zip_path, @dst)

    assert_equal [File.join(@dst, 'dir/subdir/file.txt')], extracted
    assert_equal 'hello', File.read(extracted.first)
  end

  def test_unzip_blocks_zip_slip
    zip_path = write_zip('evil.zip', '../../outside.txt' => 'owned')

    assert_raises(HELPERS::PathTraversalError) { HELPERS.unzip(zip_path, @dst) }
    refute File.exist?(File.expand_path('../../outside.txt', @dst))
  end

  def test_gunzip_keeps_orig_basename
    gz_path = write_gz('payload.gz', 'data', orig_name: '../../foo/baz.txt')

    extracted = HELPERS.unzip(gz_path, @dst)

    assert_equal [File.join(@dst, 'baz.txt')], extracted
    assert_equal 'data', File.read(extracted.first)
    refute File.exist?(File.expand_path('../../foo/baz.txt', @dst))
  end

  private

  def write_zip(name, entries)
    path = File.join(@src, name)
    Zip::File.open(path, create: true) do |zip|
      entries.each { |entry, content| zip.get_output_stream(entry) { |io| io.write(content) } }
    end
    path
  end

  def write_gz(name, content, orig_name:)
    path = File.join(@src, name)
    Zlib::GzipWriter.open(path) do |gz|
      gz.orig_name = orig_name
      gz.write(content)
    end
    path
  end
end
