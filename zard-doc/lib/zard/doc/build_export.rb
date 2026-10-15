# frozen_string_literal: true

require "json"
require "pathname"

module Zard
  module Doc
    class BuildExport
      def initialize(configuration, documents, digests)
        @configuration = configuration
        @documents = documents
        @digests = digests
      end

      def render(renderer, enricher: nil)
        declarations = renderer.export_declarations
        data = {schema: "zard-doc/v0", revision: 1,
                producer: {zard: Zard::VERSION, zard_doc: Zard::Doc::VERSION},
                layout: @configuration.layout,
                scopes: @configuration.selected_scopes.map { |name| scope(name, declarations.fetch(name)) },
                links: renderer.links.sort.to_h,
                warnings: renderer.diagnostics.map { |message| relative_message(message) }}
        data = enricher.call(data, base: @configuration.base) if enricher
        JSON.pretty_generate(data) + "\n"
      rescue JSON::GeneratorError => error
        raise BuildError, "cannot export documentation JSON: #{error.message}"
      end

      private

      def scope(name, entries)
        config = @configuration.scopes.fetch(name)
        declarations = entries.map { |entry| declaration(name, entry) }
        {name: name, destination: config.fetch(:destination),
         references: config.fetch(:references).uniq.sort,
         files: @documents.fetch(name).sort_by(&:path).map { |document| source_file(document) },
         declarations: declarations,
         pages: declarations.group_by { |item| item.fetch(:page) }.sort.map do |path, items|
           {path: path, declarations: items.map { |item| item.fetch(:id) }}
         end}
      end

      def source_file(document)
        {path: relative_path(document.path), digest: @digests.fetch(document.path),
         diagnostics: document.diagnostics.map do |diagnostic|
           {code: diagnostic.code, severity: diagnostic.severity,
            message: relative_message(diagnostic.message), span: span(diagnostic.span)}
         end}
      end

      def declaration(scope, entry)
        item = entry.fetch(:declaration)
        {id: "#{scope}:#{entry.fetch(:anchor)}", kind: item.kind, name: item.name,
         namespace: item.namespace, display_name: entry.fetch(:display_name),
         visibility: item.visibility, parameters: item.parameters,
         parameter_details: item.parameter_details&.map do |parameter|
           {kind: parameter.kind, name: parameter.name, source: parameter.source, span: span(parameter.span),
            default: parameter.default, default_span: span(parameter.default_span)}
         end,
         page: entry.fetch(:page), anchor: entry.fetch(:anchor), references: entry.fetch(:references),
         receiver: item.receiver, receiver_span: span(item.receiver_span),
         refinement: item.refinement, refinement_span: span(item.refinement_span),
         alias_target: item.alias_target, superclass: item.superclass, superclass_span: span(item.superclass_span),
         container_builder: item.container_builder, container_builder_span: span(item.container_builder_span),
         mixins: item.mixins.map { |mixin| {kind: mixin.kind, target: mixin.target, span: span(mixin.span)} },
         span: span(item.span), comment_span: span(item.comment_span),
         documentation: item.documentation.map { |tag| documentation(tag, entry.fetch(:descriptions).fetch(tag)) },
         contracts: item.contracts.map { |contract| contract(contract) }}
      end

      def documentation(tag, rendered)
        {name: tag.name, owner: tag.owner, subject: tag.subject, claim: tag.claim,
         description: tag.description, rendered_description: rendered, raw: tag.raw, span: span(tag.span)}
      end

      def contract(item)
        {channel: item.channel, payload: item.payload, note: item.note, raw: item.raw, span: span(item.span)}
      end

      def span(item)
        return unless item

        {path: relative_path(item.path), start_line: item.start_line, end_line: item.end_line,
         start_column: item.start_column, end_column: item.end_column,
         start_offset: item.start_offset, end_offset: item.end_offset}
      end

      def relative_path(path)
        Pathname.new(path).relative_path_from(Pathname.new(@configuration.base)).to_s
      end

      def relative_message(message)
        @digests.keys.sort_by { |path| -path.length }.reduce(message) do |text, path|
          text.gsub(path, relative_path(path))
        end
      end
    end
  end
end
