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

  def test_gzip_file_keeps_original_and_round_trips
    src = File.join(@dst, 'onto.ttl')
    File.write(src, "<a> <b> <c> .\n" * 1000)

    gz = LinkedData::Utils::FileHelpers.gzip_file(src)

    assert_equal "#{src}.gz", gz
    assert File.exist?(src)
    Zlib::GzipReader.open(gz) do |reader|
      assert_equal 'onto.ttl', reader.orig_name
      assert_equal File.binread(src), reader.read
    end
    assert_equal ['onto.ttl', 'onto.ttl.gz'], Dir.children(@dst).sort
  end

  def test_zip_file_keeps_original_and_round_trips
    src = File.join(@dst, 'onto.owl')
    File.write(src, "<owl/>\n" * 1000)

    zip = LinkedData::Utils::FileHelpers.zip_file(src)

    assert_equal "#{src}.zip", zip
    assert File.exist?(src)
    Zip::File.open(zip) do |z|
      assert_equal ['onto.owl'], z.entries.map(&:name)
      assert_equal File.binread(src), z.read('onto.owl')
    end
  end

  def test_zip_file_replaces_a_stale_zip
    src = File.join(@dst, 'onto.owl')
    File.write(src, 'new content')
    Zip::File.open("#{src}.zip", create: true) { |z| z.get_output_stream('onto.owl') { |o| o.write('old content') } }

    LinkedData::Utils::FileHelpers.zip_file(src)

    Zip::File.open("#{src}.zip") { |z| assert_equal 'new content', z.read('onto.owl') }
  end

  def test_compressing_compressed_files_is_a_no_op
    fh = LinkedData::Utils::FileHelpers
    gz = write_gz('BRO_v3.2.owl.gz', 'data', orig_name: 'BRO_v3.2.owl')
    [gz, './test/data/ontology_files/evoc_v2.9.zip'].each do |path|
      assert_equal path, fh.gzip_file(path)
      assert_equal path, fh.zip_file(path)
    end
  end

  def test_gzip_file_failed_verification_leaves_no_output
    src = File.join(@dst, 'onto.ttl')
    File.write(src, 'content')
    stub_singleton(Zlib::GzipReader, :open, 'mismatch') do
      assert_raises(IOError) { LinkedData::Utils::FileHelpers.gzip_file(src) }
    end
    assert_equal ['onto.ttl'], Dir.children(@dst)
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

  # No mocha here: swap a class method for the block's duration
  def stub_singleton(klass, name, value)
    original = klass.method(name)
    klass.define_singleton_method(name) { |*| value }
    yield
  ensure
    klass.define_singleton_method(name, original)
  end
end
