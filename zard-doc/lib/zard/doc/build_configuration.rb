# frozen_string_literal: true

require "yaml"
require "pathname"

module Zard
  module Doc
    class BuildConfiguration
      attr_reader :base, :docroot, :layout, :selected_scopes, :scopes

      def initialize(path, layout: nil, scopes: [])
        base = @base = File.realpath(File.dirname(File.expand_path(path)))
        text = File.read(path)
        validate_yaml_keys(Psych.parse_stream(text))
        raw = YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
        mapping(raw, %w[docroot layout scopes publication], "configuration")
        @docroot = File.expand_path(string(raw["docroot"], "docroot"), base)
        @layout = layout || raw.fetch("layout", "namespace")
        fail_build("layout must be namespace or file") unless %w[namespace file].include?(@layout)
        publication = publication_policy(raw.fetch("publication", {}), PublicationPolicy::DEFAULT)
        definitions = raw["scopes"]
        fail_build("scopes must be a nonempty mapping") unless definitions.is_a?(Hash) && !definitions.empty?
        @scopes = definitions.to_h do |name, definition|
          string(name, "scope name")
          mapping(definition, %w[destination references sources publication], "scope #{name}")
          sources = definition["sources"]
          fail_build("scope #{name} sources must be a nonempty array") unless sources.is_a?(Array) && !sources.empty?
          [name, {publication: publication_policy(definition.fetch("publication", {}), publication),
                  destination: relative(definition["destination"], "destination"),
                  references: strings(definition.fetch("references", []), "references"),
                  sources: sources.map { |source| source_mapping(source, base) }}]
        end
        @scopes.each do |name, definition|
          definition[:references].each { |reference| fail_build("unknown dependency #{reference} in scope #{name}") unless @scopes.key?(reference) }
        end
        requested = scopes.empty? ? @scopes.keys : scopes
        @selected_scopes = []
        visit = lambda do |name|
          fail_build("unknown scope #{name}") unless @scopes.key?(name)
          next if @selected_scopes.include?(name)
          @selected_scopes << name
          @scopes.fetch(name)[:references].sort.each { |reference| visit.call(reference) }
        end
        requested.sort.each { |name| visit.call(name) }
        @selected_scopes.sort!
        @selected_scopes.combination(2) do |left, right|
          a = @scopes.fetch(left).fetch(:destination)
          b = @scopes.fetch(right).fetch(:destination)
          fail_build("overlapping scope destinations: #{left} and #{right}") if a == b || a.start_with?(b + "/") || b.start_with?(a + "/")
        end
      rescue Psych::Exception, SystemCallError, ArgumentError => error
        fail_build("cannot load configuration #{path}: #{error.message}")
      end

      def source_files(name)
        definition = @scopes.fetch(name)
        roots = definition[:sources].map { |source| File.realpath(source[:root]) }
        files = {}
        definition[:sources].each do |source|
          source[:include].flat_map { |glob| Dir.glob(glob, base: source[:root], flags: File::FNM_DOTMATCH) }.uniq.sort.each do |relative_path|
            next unless relative_path.end_with?(".rb")
            next if source[:exclude].any? { |glob| File.fnmatch?(glob, relative_path, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH) }
            path = File.join(source[:root], relative_path)
            canonical = File.realpath(path)
            fail_build("source symlink escapes declared roots: #{path}") unless roots.any? { |root| canonical.start_with?(root + File::SEPARATOR) }
            next unless File.file?(canonical)
            fail_build("unreadable source: #{path}") unless File.readable?(canonical)
            output = [source[:prefix], relative_path.sub(/\.rb\z/, ".md")].reject(&:empty?).join("/")
            fail_build("conflicting output assignments for #{canonical}") if files.key?(canonical) && files[canonical] != output
            files[canonical] = output
          end
        end
        fail_build("scope #{name} selects no Ruby files") if files.empty?
        files.sort.to_h
      rescue SystemCallError => error
        fail_build("cannot discover scope #{name}: #{error.message}")
      end

      private

      def validate_yaml_keys(node)
        if node.is_a?(Psych::Nodes::Mapping)
          keys = node.children.each_slice(2).map(&:first)
          values = keys.map { |key| key.respond_to?(:value) ? key.value : nil }
          fail_build("duplicate or invalid YAML mapping key") if values.include?(nil) || values.uniq.length != values.length
        end
        node.children&.each { |child| validate_yaml_keys(child) }
      end

      def publication_policy(value, defaults)
        mapping(value, %w[visibility intent], "publication")
        {visibility: %w[public protected private], intent: %w[public internal]}.to_h do |key, allowed|
          entries = strings(value.fetch(key.to_s, defaults.fetch(key)), "publication #{key}")
          fail_build("publication #{key} must contain only #{allowed.join(", ")}") unless (entries - allowed).empty?
          [key, entries.uniq.freeze]
        end.freeze
      end

      def source_mapping(source, base)
        mapping(source, %w[root include exclude prefix], "source")
        root = File.expand_path(string(source["root"], "source root"), base)
        fail_build("missing source root: #{root}") unless File.directory?(root)
        includes = strings(source.fetch("include", ["**/*.rb"]), "include")
        excludes = strings(source.fetch("exclude", []), "exclude")
        (includes + excludes).each { |glob| relative(glob, "source glob") }
        {root: root, include: includes, exclude: excludes, prefix: relative(source.fetch("prefix", ""), "prefix", empty: true)}
      end

      def mapping(value, keys, label)
        fail_build("#{label} must be a mapping") unless value.is_a?(Hash)
        unknown = value.keys - keys
        fail_build("unknown #{label} fields: #{unknown.join(", ")}") unless unknown.empty?
      end

      def strings(value, label)
        fail_build("#{label} must be an array") unless value.is_a?(Array)
        value.each { |entry| string(entry, label) }
        value
      end

      def string(value, label)
        fail_build("#{label} must be a nonempty string") unless value.is_a?(String) && !value.empty? && !value.include?("\0")
        value
      end

      def relative(value, label, empty: false)
        return "" if empty && value == ""
        string(value, label)
        fail_build("#{label} must be a relative nonescaping path: #{value}") if Pathname.new(value).absolute? || value.split(/[\\\/]/).any? { |part| part == ".." || part == "." } || value.include?("\\")
        value.sub(%r{/+\z}, "")
      end

      def fail_build(message)
        raise BuildError.new(message, status: 2)
      end
    end
  end
end
