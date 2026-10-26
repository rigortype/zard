# frozen_string_literal: true

require "pathname"

module Zard
  module Doc
    class BuildRenderer
      attr_reader :diagnostics, :links

      def initialize(scope_documents:, scope_files:, scopes:, layout:, include_undocumented: false)
        @diagnostics = []
        @links = {}
        @scopes = scopes
        @renderers = scope_documents.keys.sort.to_h do |name|
          [name, ScopeRenderer.new(name, scope_documents.fetch(name), scope_files.fetch(name), scopes.fetch(name), layout, self, include_undocumented: include_undocumented)]
        end
      end

      def render
        pages = {}
        add_page(pages, "index.md", "# API documentation\n\n" + @renderers.map { |name, renderer| "- [#{renderer.label(name)}](#{renderer.url(renderer.index_path)})" }.join("\n") + "\n")
        @renderers.each_value do |renderer|
          renderer.pages.each { |path, text| add_page(pages, path, text) }
        end
        pages
      end

      def dependencies(name)
        @scopes.fetch(name).fetch(:references, []).uniq.filter_map { |dependency| @renderers[dependency] }
      end

      def export_declarations
        @renderers.transform_values(&:export_declarations)
      end

      def record_link(from, path, anchor)
        targets = (@links[from] ||= [])
        target = {"path" => path, "anchor" => anchor}
        targets << target unless targets.include?(target)
      end

      def warn_ambiguity(reference, origin, candidates)
        locations = candidates.map { |renderer, declaration| "#{renderer.name}:#{declaration.span.path}:#{declaration.span.start_line}" }
        message = "warning: ambiguous reference #{reference.inspect} at #{origin.span.path}:#{origin.span.start_line}; candidates: #{locations.join(", ")}"
        @diagnostics << message unless @diagnostics.include?(message)
      end

      def warn_relationship(kind, expression, origin)
        message = "warning: unresolved #{kind} documentation relationship #{expression.inspect} at #{origin.span.path}:#{origin.span.start_line}"
        @diagnostics << message unless @diagnostics.include?(message)
      end

      private

      def add_page(pages, path, text)
        raise BuildError, "output collision: #{path}" if pages.key?(path) || pages.keys.any? { |other| other.start_with?("#{path}/") || path.start_with?("#{other}/") }

        pages[path] = text
      end

      class ScopeRenderer < Renderer
        attr_reader :name, :index_path

        def initialize(name, documents, files, config, layout, build, include_undocumented: false)
          @name = name
          @build = build
          @layout = layout
          @destination = config.fetch(:destination)
          @include_undocumented = include_undocumented
          @publication = PublicationPolicy.new(config.fetch(:publication, PublicationPolicy::DEFAULT))
          @index_path = join_path("index.md")
          @declarations = documents.sort_by(&:path).flat_map(&:declarations)
          @container_names = @declarations.select { |declaration| %i[class module constant].include?(declaration.kind) }.map { |declaration| qualified_name(declaration) }
          @targets = Hash.new { |hash, key| hash[key] = [] }
          @declarations.each { |declaration| reference_names(declaration).each { |reference| @targets[reference] << declaration } }
          @paths = {}
          @anchors = {}
          @text = {}
          @descriptions = {}
          @page_owners = {}
          identities = @declarations.group_by { |declaration| anchor_identity(declaration) }
          ordinals = Hash.new(0)
          @declarations.each do |declaration|
            identity_key = anchor_identity(declaration)
            source = files.fetch(File.expand_path(declaration.span.path))
            ordinals[[identity_key, source]] += 1
            next unless renderable?(declaration)

            owner = namespace_page(declaration)
            relative = (layout == "file") ? files.fetch(File.expand_path(declaration.span.path)) : "#{owner.gsub("::", "/")}.md"
            path = join_path(relative)
            identity = (layout == "file") ? File.expand_path(declaration.span.path) : owner
            raise BuildError, "output collision: #{path}" if path == @index_path || (@page_owners.key?(path) && @page_owners[path] != identity)

            @page_owners[path] = identity
            @paths[declaration] = path
            key = identity_key
            key += "\0#{source}\0#{ordinals[[identity_key, source]]}" if identities.fetch(identity_key).length > 1
            @anchors[declaration] = "zard-#{key.bytes.map { |byte| "%02x" % byte }.join}"
          end
        end

        def pages
          @paths.each_key do |declaration|
            text = declaration.documentation.select { |tag| tag.name == :text }.map(&:description).join("\n")
            @text[declaration] = render_prose(text, declaration)
            @descriptions[declaration] = declaration.documentation.to_h do |tag|
              description = case tag.name
              when :example, :raw, :text then tag.description
              when :see then render_reference(tag.description, declaration)
              else render_prose(tag.description, declaration)
              end
              [tag, description]
            end
          end
          result = @paths.keys.group_by { |declaration| @paths.fetch(declaration) }.sort.to_h do |path, declarations|
            sections = declarations.map do |declaration|
              "#{render_declaration(declaration)}\n\nSource: #{label("#{declaration.span.path}:#{declaration.span.start_line}")}."
            end
            [path, "#{sections.join("\n\n")}\n"]
          end
          navigation = result.keys.map { |path| "- [#{label(Pathname.new(path).relative_path_from(Pathname.new(File.dirname(index_path))).to_s)}](#{relative_url(index_path, path)})" }
          result[index_path] = "# #{label(name)}\n\n#{navigation.join("\n")}\n"
          result
        end

        def lookup(candidates, path, containers: false)
          path = path.delete_prefix("::")
          candidates.each do |candidate|
            targets = @targets[candidate].uniq
            unless targets.empty?
              if (@layout == "namespace" || containers) && targets.map(&:kind).uniq.one? && targets.all? { |target| %i[class module].include?(target.kind) }
                published = targets.find { |target| renderable?(target) }
                return [:found, [published]] if published
              end
              return [:found, targets]
            end
            if path.start_with?("#", ".") && @container_names.include?(candidate.split(/[.#]/, 2).first)
              return [:shadowed, []]
            end
            first_constant = path.split(/::|[.#]/).first.to_s
            local_constant = "#{candidate.delete_suffix(path)}#{first_constant}"
            return [:shadowed, []] if !first_constant.empty? && @container_names.include?(local_constant)
          end
          [:missing, []]
        end

        def destination(declaration)
          [@paths.fetch(declaration), @anchors.fetch(declaration)]
        end

        def export_declarations
          @paths.map do |declaration, path|
            descriptions = @descriptions.fetch(declaration).to_h do |tag, description|
              [tag, (tag.name == :text) ? render_prose(tag.description, declaration) : description]
            end
            {declaration: declaration, page: path, anchor: @anchors.fetch(declaration),
             display_name: reference_names(declaration).first || display_name(declaration),
             references: reference_names(declaration), descriptions: descriptions, relationships: relationship_entries(declaration)}
          end
        end

        def relationship_targets(declaration)
          @targets.fetch(qualified_name(declaration)).select { |item| %i[class module].include?(item.kind) && published?(item) }.map do |item|
            path, anchor = destination(item)
            {scope: name, declaration_id: "#{name}:#{anchor}", path: path, anchor: anchor}
          end
        end

        def published?(declaration)
          renderable?(declaration)
        end

        def label(value)
          escape_label(value)
        end

        def url(path)
          path.bytes.map { |byte| byte.chr.match?(/[A-Za-z0-9\-._~\/]/) ? byte.chr : "%%%02X" % byte }.join
        end

        private

        def renderable?(declaration)
          @publication.include?(declaration) && (@include_undocumented || declaration.documentation.any? { |tag| tag.name != :raw })
        end

        def join_path(path)
          Pathname.new(File.join(@destination, path)).cleanpath.to_s
        end

        def anchor_identity(declaration)
          reference = reference_names(declaration).first
          [declaration.kind, reference || display_name(declaration), declaration.refinement].join("\0")
        end

        def namespace_page(declaration)
          return qualified_name(declaration) if %i[class module].include?(declaration.kind)

          if declaration.kind.to_s.start_with?("singleton_") && !declaration.refinement
            owner = reference_owner(declaration)
            return owner.delete_prefix("::") if owner&.match?(/\A(?:::)?[[:upper:]\p{Lt}][[:word:]]*(?:::[[:upper:]\p{Lt}][[:word:]]*)*\z/)
          end

          declaration.namespace || "_top-level"
        end

        def relative_url(from, to)
          url(Pathname.new(to).relative_path_from(Pathname.new(File.dirname(from))).to_s)
        end

        def resolve_scoped(reference, declaration, outer: false, containers: false)
          return if !reference || declaration.refinement

          path = reference.sub(/\A((?:::)?[[:upper:]\p{Lt}][[:word:]]*(?:::[[:upper:]\p{Lt}][[:word:]]*)*)?(?:\?\.|\.#)/) { "#{$1}." }
          candidates = if path.start_with?("::")
            [path.delete_prefix("::")]
          elsif path.start_with?("#", ".")
            owner = declaration.kind.to_s.start_with?("singleton_") ? reference_owner(declaration) : declaration.namespace
            owner = qualified_name(declaration) if %i[class module].include?(declaration.kind)
            ["#{owner&.delete_prefix("::")}#{path}"]
          else
            namespace = (!outer && %i[class module].include?(declaration.kind)) ? qualified_name(declaration) : declaration.namespace
            lexical_candidates(path, namespace)
          end
          status, targets = lookup(candidates, path, containers: containers)
          matches = targets.map { |target| [self, target] }
          if status == :missing
            matches = @build.dependencies(name).flat_map do |renderer|
              _, dependency_targets = renderer.lookup(candidates, path, containers: containers)
              dependency_targets.map { |target| [renderer, target] }
            end
          end
          if matches.length > 1
            @build.warn_ambiguity(reference, declaration, matches)
            return
          end
          match = matches.first
          return unless match

          match if match.first.published?(match.last)
        end

        def relationship_entries(declaration)
          return [] unless %i[class module].include?(declaration.kind) && !declaration.refinement

          entries = []
          entries << [:superclass, declaration.superclass, declaration.superclass_span] if declaration.superclass
          entries << [:container_builder, declaration.container_builder, declaration.container_builder_span] if declaration.container_builder
          entries.concat(declaration.mixins.map { |mixin| [mixin.kind, mixin.target, mixin.span] })
          entries.map do |kind, expression, span|
            constant = expression.match?(/\A(?:::)?[[:upper:]\p{Lt}][[:word:]]*(?:::[[:upper:]\p{Lt}][[:word:]]*)*\z/)
            match = resolve_scoped(expression, declaration, outer: kind == :superclass, containers: true) if constant && kind != :container_builder
            expected_kind = (kind == :superclass) ? :class : :module
            match = nil if match && match.last.kind != expected_kind
            targets = match ? match.first.relationship_targets(match.last) : []
            targets.each { |target| @build.record_link(@paths.fetch(declaration), target.fetch(:path), target.fetch(:anchor)) }
            status = if !targets.empty?
              :resolved
            elsif constant && kind != :container_builder
              :unresolved
            else
              :expression
            end
            @build.warn_relationship(kind, expression, declaration) unless status == :resolved
            {kind: kind, expression: expression, span: span, status: status, targets: targets}
          end
        end

        def link_destination(match, declaration)
          path, anchor = match.first.destination(match.last)
          @build.record_link(@paths.fetch(declaration), path, anchor)
          "#{relative_url(@paths.fetch(declaration), path)}##{anchor}"
        end

        def render_prose(description, declaration)
          ReferenceMarkup.rewrite(description) do |scheme, reference, label|
            yield if block_given?
            match = resolve_scoped(reference, declaration)
            next unless match
            next if (scheme == "c") != %i[class module].include?(match.last.kind)

            title = label || reference
            unless label && ReferenceMarkup.code_label?(label)
              title = title.gsub(/\\([\\\[\]])/, '\1') if label
              title = escape_label(title)
            end
            "[#{title}](#{link_destination(match, declaration)})"
          end
        end

        def render_reference(description, declaration)
          explicit = false
          prose = render_prose(description, declaration) { explicit = true }
          return prose if explicit

          reference, label = description.strip.split(/\s+/, 2)
          return description unless reference
          return super if reference.match?(/\A(?:https?:\/\/|mailto:)/)

          match = resolve_scoped(reference, declaration)
          match ? "[#{escape_label(label || reference)}](#{link_destination(match, declaration)})" : description
        end
      end
    end
  end
end
