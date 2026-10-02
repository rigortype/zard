# frozen_string_literal: true

module Zard
  module Doc
    class Renderer
      def self.render(document)
        new(document).render
      end

      def initialize(document)
        @document = document
      end

      def render
        sections = @document.declarations.filter_map { |declaration| render_declaration(declaration) }
        return "" if sections.empty?

        "#{sections.join("\n\n")}\n"
      end

      private

      def render_declaration(declaration)
        documentation = declaration.documentation.reject { |tag| tag.name == :raw }
        return if documentation.empty?

        parts = ["## `#{display_name(declaration)}(#{declaration.parameters.join(", ")})`"]
        text = documentation.select { |tag| tag.name == :text }.map(&:description)
        parts << text.join("\n") unless text.empty?

        parameters = documentation.select { |tag| tag.name == :param }
        unless parameters.empty?
          items = parameters.map { |tag| "- `#{tag.subject}` — #{tag.description}" }
          parts << "### Parameters\n\n#{items.join("\n")}"
        end

        returns = documentation.select { |tag| tag.name == :return }
        parts << "### Returns\n\n#{returns.map(&:description).join("\n\n")}" unless returns.empty?

        yield_parameters = documentation.select { |tag| tag.name == :yieldparam }
        unless yield_parameters.empty?
          items = yield_parameters.map { |tag| "- `#{tag.subject}` — #{tag.description}" }
          parts << "### Yield parameters\n\n#{items.join("\n")}"
        end

        yield_returns = documentation.select { |tag| tag.name == :yieldreturn }
        parts << "### Yields\n\n#{yield_returns.map(&:description).join("\n\n")}" unless yield_returns.empty?
        parts.join("\n\n")
      end

      def display_name(declaration)
        return declaration.name unless declaration.namespace

        separator = (declaration.kind == :singleton_method) ? "." : "#"
        "#{declaration.namespace}#{separator}#{declaration.name}"
      end
    end
  end
end
