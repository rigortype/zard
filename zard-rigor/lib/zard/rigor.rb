# frozen_string_literal: true

require "json"
require "digest"
require "digest/xxhash"
require "open3"
require "pathname"
require_relative "rigor/version"
require_relative "rigor/document"

module Zard
  module Rigor
    class Error < StandardError; end

    # The external process is the only Rigor dependency. No analyzer classes are loaded.
    class Lens
      def initialize(root:, command: "rigor", workers: 4, config: nil, runner: Open3.method(:capture3))
        @root = File.realpath(root)
        @command = command
        @workers = workers
        @config = config
        @runner = runner
      end

      def enrich(export, base:)
        data = JSON.parse(JSON.generate(export))
        raise Error, "Expected zard-doc/v0 revision 1" unless data.values_at("schema", "revision") == ["zard-doc/v0", 1]

        base = File.realpath(base)
        selected = data.fetch("scopes").flat_map { |scope| scope.fetch("files") }.to_h do |file|
          absolute = project_file(File.expand_path(file.fetch("path"), base))
          bytes = File.binread(absolute)
          raise Error, "ZARD source changed before lens: #{relative(absolute)}" unless Digest::SHA256.hexdigest(bytes) == file.fetch("digest")

          [absolute, bytes]
        end
        raise Error, "No source files selected for lens" if selected.empty?

        paths = selected.keys.sort
        arguments = paths.map { |file| "./#{relative(file)}" }
        options = ["--format=json", "--workers", @workers.to_s]
        options += ["--config", @config] if @config
        invoke = -> { @runner.call(@command, "lens", *options, *arguments, chdir: @root) }
        stdout, stderr, process = defined?(Bundler) ? Bundler.with_unbundled_env(&invoke) : invoke.call
        unless [0, 1].include?(process.exitstatus)
          raise Error, "rigor lens failed (exit #{process.exitstatus || "signal"}): #{stderr.strip}"
        end
        document = Document.new(JSON.parse(stdout), root: @root, selected: selected, arguments: arguments, status: process.exitstatus)
        paths.each do |file|
          raise Error, "Source changed during lens: #{relative(file)}" unless File.binread(file) == selected.fetch(file)
        end
        data["lens"] = document.bind(data, base: base, project: Pathname.new(@root).relative_path_from(Pathname.new(base)).to_s)
        data
      rescue JSON::ParserError => error
        raise Error, "rigor lens returned invalid or truncated JSON: #{error.message}"
      rescue SystemCallError => error
        raise Error, "Cannot run/read rigor lens; install Rigor 0.4.3 and check the configured executable/root: #{error.message}"
      rescue KeyError, TypeError => error
        raise Error, "Malformed lens/export data: #{error.message}"
      end

      private

      def project_file(file)
        actual = File.realpath(file)
        raise Error, "Lens source escapes project root" unless actual.start_with?(@root + File::SEPARATOR)

        actual
      end

      def relative(file)
        Pathname.new(file).relative_path_from(Pathname.new(@root)).to_s
      end
    end
  end
end
