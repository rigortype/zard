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
        return unless declaration.visibility == :public

        documentation = declaration.documentation.reject { |tag| tag.name == :raw }
        return if documentation.empty?

        parts = [heading(declaration)]
        text = documentation.select { |tag| tag.name == :text }.map(&:description)
        parts << text.join("\n") unless text.empty?

        deprecated = documentation.select { |tag| tag.name == :deprecated }
        parts << "### Deprecated\n\n#{deprecated.map(&:description).join("\n\n")}" unless deprecated.empty?

        notes = documentation.select { |tag| tag.name == :note }
        parts << "### Notes\n\n#{notes.map(&:description).join("\n\n")}" unless notes.empty?

        examples = documentation.select { |tag| tag.name == :example }
        parts << "### Examples\n\n#{examples.map(&:description).join("\n\n")}" unless examples.empty?

        parameters = documentation.select { |tag| tag.name == :param }
        unless parameters.empty?
          items = parameters.map { |tag| list_item("`#{tag.subject}` — ", tag.description) }
          parts << "### Parameters\n\n#{items.join("\n")}"
        end

        returns = documentation.select { |tag| tag.name == :return }
        parts << "### Returns\n\n#{returns.map(&:description).join("\n\n")}" unless returns.empty?

        documentation.select { |tag| tag.name == :option }.group_by(&:owner).each do |owner, options|
          items = options.map { |tag| list_item("`#{tag.subject}` — ", tag.description) }
          parts << "### Options for `#{owner}`\n\n#{items.join("\n")}"
        end

        raises = documentation.select { |tag| tag.name == :raise }
        unless raises.empty?
          items = raises.map { |tag| list_item("`#{tag.subject}` — ", tag.description) }
          parts << "### Raises\n\n#{items.join("\n")}"
        end

        yield_parameters = documentation.select { |tag| tag.name == :yieldparam }
        unless yield_parameters.empty?
          items = yield_parameters.map { |tag| list_item("`#{tag.subject}` — ", tag.description) }
          parts << "### Yield parameters\n\n#{items.join("\n")}"
        end

        yield_returns = documentation.select { |tag| tag.name == :yieldreturn }
        parts << "### Yields\n\n#{yield_returns.map(&:description).join("\n\n")}" unless yield_returns.empty?

        see_also = documentation.select { |tag| tag.name == :see }
        unless see_also.empty?
          items = see_also.map { |tag| list_item("", tag.description) }
          parts << "### See also\n\n#{items.join("\n")}"
        end
        parts.join("\n\n")
      end

      def heading(declaration)
        case declaration.kind
        when :class
          "## Class `#{qualified_name(declaration)}`"
        when :module
          "## Module `#{qualified_name(declaration)}`"
        when :constant
          "## Constant `#{qualified_name(declaration)}`"
        when :instance_attribute_reader, :singleton_attribute_reader
          "## Attribute reader `#{display_name(declaration)}`"
        when :instance_attribute_writer, :singleton_attribute_writer
          "## Attribute writer `#{display_name(declaration)}`"
        when :instance_attribute_accessor, :singleton_attribute_accessor
          "## Attribute accessor `#{display_name(declaration)}`"
        else
          "## `#{display_name(declaration)}(#{declaration.parameters.join(", ")})`"
        end
      end

      def qualified_name(declaration)
        [declaration.namespace, declaration.name].compact.join("::")
      end

      def display_name(declaration)
        return declaration.name unless declaration.namespace

        separator = declaration.kind.to_s.start_with?("singleton_") ? "." : "#"
        "#{declaration.namespace}#{separator}#{declaration.name}"
      end

      def list_item(prefix, description)
        first, *continuation = description.split("\n", -1)
        lines = ["- #{prefix}#{first}"]
        continuation.each { |line| lines << (line.empty? ? "" : "  #{line}") }
        lines.join("\n")
      end
    end
  end
end
