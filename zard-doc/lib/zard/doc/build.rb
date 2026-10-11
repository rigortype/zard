# frozen_string_literal: true

require "zard/doc"

module Zard
  module Doc
    class BuildError < StandardError
      attr_reader :status

      def initialize(message, status: 2)
        super(message)
        @status = status
      end
    end
  end
end

require_relative "build_configuration"
require_relative "build_publisher"
require_relative "build_renderer"

module Zard
  module Doc
    class Build
      attr_reader :diagnostics

      def initialize(path, layout: nil, scopes: [])
        @configuration = BuildConfiguration.new(path, layout: layout, scopes: scopes)
        @partial = !scopes.empty?
        @diagnostics = []
      end

      def run
        files = {}
        documents = {}
        input_errors = []
        @configuration.selected_scopes.each do |name|
          files[name] = @configuration.source_files(name)
          documents[name] = files.fetch(name).keys.filter_map do |path|
            document = Zard.parse(File.read(path), path: path)
            document.diagnostics.each { |diagnostic| @diagnostics << format_diagnostic(diagnostic) }
            document
          rescue SystemCallError => error
            input_errors << "#{path}: #{error.message}"
            nil
          end
        end
        @diagnostics.concat(input_errors)
        return 2 unless input_errors.empty?
        return 1 if documents.values.flatten.any? { |document| document.diagnostics.any? { |diagnostic| diagnostic.severity == :error } }

        renderer = BuildRenderer.new(scope_documents: documents, scope_files: files,
          scopes: @configuration.scopes, layout: @configuration.layout)
        pages = renderer.render
        @diagnostics.concat(renderer.diagnostics)
        destinations = @configuration.selected_scopes.to_h do |name|
          [name, @configuration.scopes.fetch(name).fetch(:destination)]
        end
        publisher = BuildPublisher.new(@configuration.docroot)
        if @partial
          pages["index.md"] = scope_index(publisher.scopes.merge(destinations))
          publisher.publish(pages, selected_scopes: destinations, links: renderer.links)
        else
          publisher.publish(pages, scopes: destinations, links: renderer.links)
        end
        0
      end

      private

      def scope_index(destinations)
        links = destinations.sort.map do |name, destination|
          label = name.gsub(/[&<>]/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;").gsub(/[\\\[\]`*_~]/) { |character| "\\#{character}" }
          path = "#{destination}/index.md".b.gsub(/[^A-Za-z0-9._~\/-]/) { |byte| "%%%02X" % byte.ord }
          "- [#{label}](#{path})"
        end
        "# API documentation\n\n#{links.join("\n")}\n"
      end

      def format_diagnostic(diagnostic)
        span = diagnostic.span
        "#{span.path}:#{span.start_line}:#{span.start_column + 1}: #{diagnostic.severity} #{diagnostic.code} #{diagnostic.message}"
      end
    end

    private_constant :BuildError, :BuildConfiguration, :BuildPublisher, :BuildRenderer, :Build
  end
end
