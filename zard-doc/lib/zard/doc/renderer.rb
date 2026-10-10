# frozen_string_literal: true

module Zard
  module Doc
    class Renderer
      def self.render(document)
        new([document]).render
      end

      def self.render_documents(documents)
        new(documents).render
      end

      def initialize(documents)
        @documents = documents
        @container_names = documents.flat_map(&:declarations).select { |declaration| %i[class module constant].include?(declaration.kind) }.map { |declaration| qualified_name(declaration) }
        @targets = Hash.new { |hash, key| hash[key] = [] }
        documents.flat_map(&:declarations).each do |declaration|
          reference_names(declaration).each { |name| @targets[name] << declaration }
        end
        @anchors = {}
        documents.flat_map(&:declarations).each do |declaration|
          next unless renderable?(declaration)

          declaration.documentation.select { |tag| tag.name == :see }.each do |tag|
            reference = tag.description.strip.split(/\s+/, 2).first
            target = resolve_reference(reference, declaration)
            @anchors[target] = anchor(target) if target
          end
        end
      end

      def render
        @documents.filter_map do |document|
          sections = document.declarations.filter_map { |declaration| render_declaration(declaration) }
          "#{sections.join("\n\n")}\n" unless sections.empty?
        end.join("\n")
      end

      private

      def render_declaration(declaration)
        return unless renderable?(declaration)

        documentation = declaration.documentation.reject { |tag| tag.name == :raw }

        parts = [heading(declaration)]
        parts.unshift("<a id=\"#{@anchors[declaration]}\"></a>") if @anchors.key?(declaration)
        parts << "Superclass: `#{declaration.superclass}`." if declaration.superclass
        parts << render_container_builder(declaration) if declaration.container_builder
        append_mixins(parts, declaration)
        parts << "Alias of `#{display_alias_target(declaration)}`." if declaration.alias_target
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
          items = see_also.map { |tag| list_item("", render_reference(tag.description, declaration)) }
          parts << "### See also\n\n#{items.join("\n")}"
        end
        parts.join("\n\n")
      end

      def heading(declaration)
        return "## Alias `#{display_name(declaration)}`" if declaration.alias_target

        case declaration.kind
        when :class
          "## Class `#{qualified_name(declaration)}`"
        when :module
          "## Module `#{qualified_name(declaration)}`"
        when :constant
          "## Constant `#{qualified_name(declaration)}`"
        when :refinement
          "## Refinement `#{refinement_owner(declaration)}`"
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

      def append_mixins(parts, declaration)
        {include: "Includes", prepend: "Prepends", extend: "Extends"}.each do |kind, heading|
          targets = declaration.mixins.select { |mixin| mixin.kind == kind }.map(&:target)
          parts << "### #{heading}\n\n#{targets.map { |target| "- `#{target}`" }.join("\n")}" unless targets.empty?
        end
      end

      def render_container_builder(declaration)
        builder = declaration.container_builder
        label = if declaration.kind == :module
          "Module builder"
        else
          "Class builder"
        end
        return "#{label}: `#{builder}`." unless builder.include?("\n")

        "#{label}:\n\n```ruby\n#{dedent_continuation(builder)}\n```"
      end

      def dedent_continuation(source)
        first, *continuation = source.lines(chomp: true)
        margins = continuation.reject { |line| line.strip.empty? }.map { |line| line[/\A[\t ]*/].length }
        margin = margins.min || 0
        [first, *continuation.map { |line| line[margin..] }].join("\n")
      end

      def qualified_name(declaration)
        [declaration.namespace, declaration.name].compact.join("::")
      end

      def renderable?(declaration)
        declaration.visibility == :public && declaration.documentation.any? { |tag| tag.name != :raw }
      end

      def reference_names(declaration)
        return [] if declaration.refinement || declaration.kind == :refinement
        return [qualified_name(declaration)] if %i[class module constant].include?(declaration.kind)

        singleton = declaration.kind.to_s.start_with?("singleton_")
        owner = singleton ? reference_owner(declaration) : declaration.namespace
        return [] if singleton && !owner && declaration.namespace
        return [] if owner && !owner.match?(/\A(?:::)?[[:upper:]\p{Lt}][[:word:]]*(?:::[[:upper:]\p{Lt}][[:word:]]*)*\z/)

        name = "#{owner&.delete_prefix("::")}#{singleton ? "." : "#"}#{declaration.name}"
        name += "=" if declaration.kind.to_s.end_with?("attribute_writer")
        declaration.kind.to_s.end_with?("attribute_accessor") ? [name, "#{name}="] : [name]
      end

      def resolve_reference(reference, declaration)
        return unless reference && !declaration.refinement

        path = reference.sub(/\A((?:::)?[[:upper:]\p{Lt}][[:word:]]*(?:::[[:upper:]\p{Lt}][[:word:]]*)*)?(?:\?\.|\.#)/) { "#{$1}." }
        if path.start_with?("::")
          candidates = [path.delete_prefix("::")]
        elsif path.start_with?("#", ".")
          owner = declaration.kind.to_s.start_with?("singleton_") ? reference_owner(declaration) : declaration.namespace
          owner = qualified_name(declaration) if %i[class module].include?(declaration.kind)
          candidates = ["#{owner&.delete_prefix("::")}#{path}"]
        else
          namespace = declaration.namespace
          namespace = qualified_name(declaration) if %i[class module].include?(declaration.kind)
          candidates = lexical_candidates(path, namespace)
        end
        candidates.each do |candidate|
          targets = @targets[candidate].uniq
          if targets.empty?
            first_constant = path.split(/::|[.#]/).first.to_s
            local_constant = "#{candidate.delete_suffix(path)}#{first_constant}"
            return nil if !first_constant.empty? && @container_names.include?(local_constant)

            next
          end

          return targets.first if targets.length == 1 && renderable?(targets.first)

          return nil
        end
        nil
      end

      def lexical_candidates(path, namespace)
        parts = namespace.to_s.split("::")
        parts.length.downto(0).map { |length| [*parts.first(length), path].join("::") }
      end

      def reference_owner(declaration)
        owner = singleton_owner(declaration)
        return owner unless owner && declaration.receiver && declaration.receiver != "self"
        return owner.delete_prefix("::") if owner.start_with?("::")
        return owner unless declaration.namespace

        lexical_candidates(owner, declaration.namespace).find { |candidate| @container_names.include?(candidate) }
      end

      def anchor(declaration)
        "zard-#{reference_names(declaration).first.bytes.map { |byte| byte.to_s(16).rjust(2, "0") }.join}"
      end

      def render_reference(description, declaration)
        reference, label = description.strip.split(/\s+/, 2)
        return description unless reference

        destination = if reference.match?(/\A(?:https?:\/\/|mailto:)/)
          reference.gsub(/[\\()< >]/) { |character| "%%%02X" % character.ord }.gsub("&", "&amp;")
        elsif (target = resolve_reference(reference, declaration))
          "##{@anchors.fetch(target)}"
        end
        return description unless destination

        title = (label || reference).gsub(/[&<>]/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;").gsub(/[\\\[\]]/) { |character| "\\#{character}" }
        "[#{title}](#{destination})"
      end

      def display_name(declaration)
        if declaration.refinement
          separator = declaration.kind.to_s.start_with?("singleton_") ? "." : "#"
          return "#{refinement_owner(declaration)}#{separator}#{declaration.name}"
        end

        if declaration.kind.to_s.start_with?("singleton_")
          owner = singleton_owner(declaration)
          return owner ? "#{owner}.#{declaration.name}" : declaration.name
        end
        return declaration.name unless declaration.namespace

        "#{declaration.namespace}##{declaration.name}"
      end

      def display_alias_target(declaration)
        if declaration.refinement
          separator = declaration.kind.to_s.start_with?("singleton_") ? "." : "#"
          return "#{refinement_owner(declaration)}#{separator}#{declaration.alias_target}"
        end

        if declaration.kind.to_s.start_with?("singleton_")
          owner = singleton_owner(declaration)
          return owner ? "#{owner}.#{declaration.alias_target}" : declaration.alias_target
        end
        return declaration.alias_target unless declaration.namespace

        "#{declaration.namespace}##{declaration.alias_target}"
      end

      def singleton_owner(declaration)
        return declaration.receiver unless declaration.receiver.nil? || declaration.receiver == "self"

        declaration.namespace || declaration.receiver
      end

      def refinement_owner(declaration)
        namespace = declaration.namespace
        target = declaration.refinement || declaration.name
        namespace ? "#{namespace}[#{target}]" : "[#{target}]"
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
