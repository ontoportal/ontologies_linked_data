require 'net/http'
require 'uri'
require 'zip'
require 'zlib'
require 'tmpdir'
require 'fileutils'

module LinkedData
  module Utils
    module FileHelpers

      # Raised when an archive entry would land outside the extraction folder (Zip Slip)
      class PathTraversalError < StandardError; end

      # Archive signatures, read from the first bytes instead of shelling out to `file`.
      # Empty, spanned and self-extracting zips start differently: unsupported.
      ZIP_MAGIC = "PK\x03\x04".b
      GZIP_MAGIC = "\x1F\x8B".b

      # Tarballs are gzip too, but gunzipping them yields a .tar, not an ontology
      TARBALL_SUFFIXES = %w[.tar.gz .tgz].freeze

      MACOS_METADATA_DIR = '__MACOSX/'.freeze
      MAX_FILENAME_LENGTH = 255

      def self.zip?(file_path)
        File.open(file_path, 'rb') { |f| f.read(ZIP_MAGIC.bytesize) } == ZIP_MAGIC
      rescue Errno::ENOENT, Errno::EISDIR
        false
      end

      def self.gzip?(file_path)
        # Name-based only: a renamed tarball still passes as a single .gz payload
        return false if File.basename(file_path.to_s).downcase.end_with?(*TARBALL_SUFFIXES)

        File.open(file_path, 'rb') { |f| f.read(GZIP_MAGIC.bytesize) } == GZIP_MAGIC
      rescue Errno::ENOENT, Errno::EISDIR
        false
      end

      # Entry names (not extracted paths), e.g. ["onto/main.owl", "onto/imports.owl"]
      def self.filenames_in_archive(file_path)
        file_path = file_path.to_s
        raise ArgumentError, "File path #{file_path} not found" unless File.exist?(file_path)

        if gzip?(file_path)
          Zlib::GzipReader.open(file_path) { |gz| return [gzip_entry_name(file_path, gz)] }
        end
        raise StandardError, "Unsupported file format: #{File.extname(file_path)}" unless zip?(file_path)

        Zip::File.open(file_path) do |zip|
          zip.entries.reject { |entry| skipped_entry?(entry) }.map(&:name)
        end
      end

      # Returns the absolute paths written under dst_folder
      def self.unzip(file_path, dst_folder)
        file_path = file_path.to_s
        dst_folder = dst_folder.to_s
        raise ArgumentError, "File path #{file_path} not found" unless File.exist? file_path
        raise ArgumentError, "Folder path #{dst_folder} not found" unless Dir.exist? dst_folder

        # A .gz holds a single payload named by its header, e.g. pizza.owl.gz -> pizza.owl
        if gzip?(file_path)
          Zlib::GzipReader.open(file_path) do |gz|
            return [extract_entry(dst_folder, gzip_entry_name(file_path, gz), gz)]
          end
        end
        raise StandardError, "Unsupported file format: #{File.extname(file_path)}" unless zip?(file_path)

        Zip::File.open(file_path) do |zip|
          zip.entries.reject { |entry| skipped_entry?(entry) }.map do |entry|
            entry.get_input_stream { |input| extract_entry(dst_folder, entry.name, input) }
          end
        end
      end

      def self.zip_file(file_path)
        return file_path if self.zip?(file_path)

        zip_file_path = "#{file_path}.zip"
        Zip::File.open(zip_file_path, create: true) do |zipfile|
          # Add the file to the zip
          begin
            zipfile.add(File.basename(file_path), file_path)
          rescue Zip::EntryExistsError
          end

        end
        zip_file_path
      end

      def self.automaster?(path, formats)
        self.automaster(path, formats) != nil
      end

      def self.automaster(path, formats)
        files = self.filenames_in_archive(path)
        zip_basename = File.basename(path, '.zip')
        Array(formats).each do |format|
          basename = File.basename(zip_basename, format)
          match = files.find { |f| File.basename(f, format).downcase.eql?(basename.downcase) }
          return match if match
        end
        nil
      end

      def self.repeated_names_in_file_list(file_list)
        return file_list.group_by {|x| x.split('/')[-1]}.select { |k,v| v.length > 1}
      end

      def self.exists_and_file(path)
        path = path.to_s
        return (File.exist?(path) and (not File.directory?(path)))
      end

      def self.download_file(uri, limit = 10)
        raise ArgumentError, 'HTTP redirect too deep' if limit == 0

        uri = URI(uri) unless uri.kind_of?(URI)

        if uri.kind_of?(URI::FTP)
          file, filename = download_file_ftp(uri)
        else
          file = Tempfile.new('ont-rest-file')
          filename = nil
          http_session = Net::HTTP.new(uri.host, uri.port)
          http_session.verify_mode = OpenSSL::SSL::VERIFY_NONE
          http_session.use_ssl = (uri.scheme == 'https')
          http_session.start do |http|
            http.read_timeout = 1800
            http.request_get(uri.request_uri, {'Accept-Encoding' => 'gzip'}) do |res|
              if res.kind_of?(Net::HTTPRedirection)
                new_loc = res['location']
                if new_loc.match(/^(http:\/\/|https:\/\/)/)
                  uri = new_loc
                else
                  uri.path = new_loc
                end
                return download_file(uri, limit - 1)
              end

              raise Net::HTTPBadResponse.new("#{uri.request_uri}: #{res.code}") if res.code.to_i >= 400

              file_size = res.read_header['content-length'].to_i
              begin
                content_disposition = res.read_header['content-disposition']
                filenames = content_disposition.match(/filename=\"(.*)\"/) || content_disposition.match(/filename=(.*)/)
                filename = filenames[1] if filename.nil?
              rescue
                filename = LinkedData::Utils::Triples.last_iri_fragment(uri.request_uri) if filename.nil?
              end

              file.write(res.body)

              if res.header['Content-Encoding'].eql?('gzip')
                uncompressed_file = Tempfile.new('uncompressed-ont-rest-file')
                file.rewind
                sio = StringIO.new(file.read)
                gz = Zlib::GzipReader.new(sio)
                uncompressed_file.write(gz.read())
                file.close
                file = uncompressed_file
                gz.close()
              end
            end
          end
          file.close
        end

        return file, filename
      end

      def self.download_file_ftp(url)
        url = URI.parse(url) unless url.kind_of?(URI)
        ftp = Net::FTP.new(url.host, url.user, url.password)
        ftp.passive = true
        ftp.login
        filename = LinkedData::Utils::Triples.last_iri_fragment(url.path)
        temp_dir = Dir.tmpdir
        temp_file_path = File.join(temp_dir, filename)
        ftp.getbinaryfile(url.path, temp_file_path)
        file = File.new(temp_file_path)
        return file, filename
      end

      # Stream one entry to disk; never leave a truncated file behind
      def self.extract_entry(dst_folder, name, input)
        dest = safe_join(dst_folder, name)
        FileUtils.mkdir_p(File.dirname(dest))
        File.open(dest, 'wb') { |f| IO.copy_stream(input, f) }
        dest
      rescue StandardError
        FileUtils.rm_f(dest) if dest
        raise
      end

      # Resolve an archive entry under base, refusing anything that escapes it
      # e.g. safe_join('/data/unzipped', '../../etc/cron.d/x') -> PathTraversalError
      def self.safe_join(base, name)
        base = File.expand_path(base)
        target = File.expand_path(File.join(base, name))
        raise PathTraversalError, "Path traversal: #{name}" unless target.start_with?(base + File::SEPARATOR)

        target
      end

      # Directories are implied by file paths, symlinks may point outside dst_folder,
      # hidden files are OS clutter (__MACOSX/, .DS_Store, ._onto.owl)
      def self.skipped_entry?(entry)
        return true if entry.directory? || entry.symlink?

        entry.name.start_with?(MACOS_METADATA_DIR) || File.basename(entry.name).start_with?('.')
      end

      # Header name, else the archive name minus .gz; always a bare basename
      # e.g. orig_name "../../x\n.owl" -> "x.owl"
      def self.gzip_entry_name(file_path, gz)
        name = File.basename(gz.orig_name.to_s).gsub(/[[:cntrl:]]/, '')
        name = File.basename(file_path, File.extname(file_path)) if name.empty?
        name[0, MAX_FILENAME_LENGTH]
      end

      private_class_method :extract_entry, :safe_join, :skipped_entry?, :gzip_entry_name

    end
  end
end
