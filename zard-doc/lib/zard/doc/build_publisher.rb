# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "tmpdir"
require "pathname"

module Zard
  module Doc
    class BuildPublisher
      MANIFEST = ".zard-manifest.json"

      def initialize(docroot)
        expanded = File.expand_path(docroot)
        fail_build("output symlink is not allowed: #{expanded}") if File.symlink?(expanded)
        ancestor = File.dirname(expanded)
        suffix = [File.basename(expanded)]
        until File.exist?(ancestor) || File.symlink?(ancestor)
          suffix.unshift(File.basename(ancestor))
          ancestor = File.dirname(ancestor)
        end
        @docroot = File.join(File.realpath(ancestor), *suffix)
      rescue SystemCallError => error
        fail_build("cannot resolve documentation root: #{error.message}")
      end

      def scopes
        manifest.fetch("scopes")
      end

      def publish(pages, selected_scopes: nil, scopes: {})
        previous = manifest
        old_pages = previous.fetch("pages")
        old_pages.each do |path, checksum|
          target = safe_path(path)
          fail_build("managed page was edited or removed: #{target}; restore it before rebuilding") unless File.file?(target) && Digest::SHA256.file(target).hexdigest == checksum
        end
        scope_map = selected_scopes ? previous.fetch("scopes").merge(selected_scopes) : scopes
        validate_scopes(scope_map)
        destinations = selected_scopes&.flat_map { |name, destination| [destination, previous.fetch("scopes")[name]] }&.compact
        removed = old_pages.keys.select { |path| !selected_scopes || path == "index.md" || destinations.any? { |destination| path.start_with?(destination + "/") } }
        retained = old_pages.except(*removed)
        pages.each do |path, content|
          target = safe_path(path)
          fail_build("page content must be text: #{path}") unless content.is_a?(String)
          fail_build("output collides with retained scope: #{path}") if retained.key?(path)
          fail_build("output collides with unowned file: #{target}") if File.exist?(target) && !old_pages.key?(path)
        end
        all_paths = retained.keys + pages.keys
        all_paths.each { |path| fail_build("output file/directory collision: #{path}") if all_paths.any? { |other| other.start_with?(path + "/") } }
        checksums = retained.merge(pages.transform_values { |content| Digest::SHA256.hexdigest(content) })
        payload = JSON.pretty_generate({"version" => 1, "pages" => checksums.sort.to_h, "scopes" => scope_map.sort.to_h}) + "\n"
        transaction(pages.merge(MANIFEST => payload), (removed + pages.keys + [MANIFEST]).uniq)
      rescue SystemCallError, IOError => error
        fail_build("cannot publish documentation: #{error.message}")
      end

      private

      def manifest
        target = safe_path(MANIFEST, manifest: true)
        return {"version" => 1, "pages" => {}, "scopes" => {}} unless File.exist?(target)
        fail_build("invalid manifest: #{target}") unless File.file?(target)
        data = JSON.parse(File.read(target))
        valid = data.is_a?(Hash) && data.keys.sort == %w[pages scopes version] && data["version"] == 1 && data["pages"].is_a?(Hash)
        fail_build("invalid manifest schema: #{target}") unless valid
        data["pages"].each do |path, checksum|
          safe_path(path)
          fail_build("invalid manifest checksum for #{path}") unless checksum.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(checksum)
        end
        validate_scopes(data["scopes"])
        data
      rescue JSON::ParserError, SystemCallError => error
        fail_build("cannot read generation manifest: #{error.message}")
      end

      def validate_scopes(scope_map)
        fail_build("invalid manifest scopes") unless scope_map.is_a?(Hash)
        scope_map.each do |name, destination|
          fail_build("invalid scope name") unless name.is_a?(String) && !name.empty?
          safe_path(destination)
        end
        scope_map.to_a.combination(2) do |(left, a), (right, b)|
          fail_build("overlapping scope destinations: #{left} and #{right}") if a == b || a.start_with?(b + "/") || b.start_with?(a + "/")
        end
      end

      def safe_path(path, manifest: false)
        invalid = !path.is_a?(String) || path.empty? || path.include?("\0") || path.include?("\\") || Pathname.new(path).absolute? || path.split("/", -1).any? { |part| ["", ".", ".."].include?(part) }
        fail_build("unsafe output path: #{path.inspect}") if invalid || (!manifest && path == MANIFEST)
        target = File.join(@docroot, path)
        current = target
        loop do
          fail_build("output symlink is not allowed: #{current}") if File.symlink?(current)
          parent = File.dirname(current)
          break if parent == current
          current = parent
        end
        target
      end

      def transaction(pages, affected)
        FileUtils.mkdir_p(File.dirname(@docroot))
        staging = Dir.mktmpdir(".zard-build-", File.dirname(@docroot))
        backup = File.join(staging, "backup")
        prepared = File.join(staging, "prepared")
        existed = {}
        affected.each do |path|
          target = safe_path(path, manifest: path == MANIFEST)
          existed[path] = File.file?(target)
          next unless existed[path]
          saved = File.join(backup, path)
          FileUtils.mkdir_p(File.dirname(saved))
          FileUtils.cp(target, saved)
        end
        pages.each do |path, content|
          target = File.join(prepared, path)
          FileUtils.mkdir_p(File.dirname(target))
          File.write(target, content)
        end
        changed = []
        begin
          affected.each do |path|
            target = safe_path(path, manifest: path == MANIFEST)
            changed << path
            if pages.key?(path)
              FileUtils.mkdir_p(File.dirname(target))
              File.rename(File.join(prepared, path), target)
            elsif File.exist?(target)
              File.unlink(target)
            end
          end
        rescue SystemCallError, IOError, BuildError => error
          begin
            changed.reverse_each do |path|
              target = safe_path(path, manifest: path == MANIFEST)
              if existed[path]
                FileUtils.cp(File.join(backup, path), target)
              elsif File.file?(target)
                File.unlink(target)
              end
            end
          rescue SystemCallError, IOError, BuildError => recovery_error
            retained_backup = true
            fail_build("publication failed: #{error.message}; recovery failed: #{recovery_error.message}; restore files from #{backup}")
          end
          fail_build("publication failed; previous pages restored: #{error.message}")
        end
      ensure
        FileUtils.remove_entry(staging) if staging && !retained_backup
      end

      def fail_build(message)
        raise BuildError.new(message, status: 2)
      end
    end
  end
end
