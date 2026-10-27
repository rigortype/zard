# frozen_string_literal: true

require "rbs"

module Zard
  module Rigor
    class TypeReferences
      PREFIX = "class ZardSignature\n  def call: "
      NAMED_TYPES = [RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Interface].freeze

      def initialize(export, members)
        @scopes = export.fetch("scopes").to_h { |scope| [scope.fetch("name"), scope] }
        @members = members.to_h { |member| [member.fetch("key"), member] }
        @indexes = @scopes.transform_values do |scope|
          scope.fetch("declarations").select { |row| %w[class module constant].include?(row.fetch("kind")) && !row["refinement"] }
            .group_by { |row| row.fetch("display_name").delete_prefix("::") }
        end
        @parsed = {}
      end

      def attach(binding)
        references = []
        diagnostics = []
        binding.fetch("member_keys").each do |key|
          member = @members.fetch(key)
          member.fetch("overloads").each_with_index do |overload, index|
            text = overload["rbs"]
            next unless text

            occurrences, error = @parsed[text] ||= occurrences(text)
            if error
              diagnostics << "#{binding.fetch("scope")}:#{member.fetch("owner")}#{(member.fetch("scope") == "singleton") ? "." : "#"}#{member.fetch("name")}: type references unavailable for overload #{index}: #{error}"
              next
            end
            occurrences.each do |occurrence|
              candidates = resolve(binding.fetch("scope"), member.fetch("owner"), occurrence.fetch("name"))
              supported = candidates.select { |_, row| %w[class module].include?(row.fetch("kind")) }
              status = if candidates.one? && supported.one?
                "resolved"
              elsif candidates.length > 1
                "ambiguous"
              else
                "unresolved"
              end
              references << occurrence.merge("member_key" => key, "overload" => index, "status" => status,
                "targets" => supported.map { |scope, row| target(scope, row) })
              next if status == "resolved"

              locations = candidates.map do |scope, row|
                span = row.fetch("span")
                "#{scope}:#{row.fetch("display_name")} at #{span.fetch("path")}:#{span.fetch("start_line")}"
              end
              diagnostics << "#{binding.fetch("scope")}:#{member.fetch("owner")}##{member.fetch("name")}: #{status} type reference #{occurrence.fetch("name")} (#{locations.empty? ? "no documented declaration" : locations.join(", ")})"
            end
          end
        end
        binding.merge("type_references" => references, "type_reference_diagnostics" => diagnostics.uniq)
      end

      private

      def occurrences(text)
        _, _, declarations = RBS::Parser.parse_signature("#{PREFIX}#{text}\nend\n")
        declaration = declarations.first
        method = declaration&.members&.first
        unless declarations.one? && declaration.members.one? && method.is_a?(RBS::AST::Members::MethodDefinition) && method.overloads.one?
          return [[], "unsupported signature structure"]
        end
        signature = method.overloads.first.method_type
        nodes = signature.each_type.to_a
        signature.type_params.each do |parameter|
          nodes.concat([parameter.upper_bound_type, parameter.lower_bound_type, parameter.default_type].compact)
        end
        references = []
        until nodes.empty?
          node = nodes.shift
          nodes.concat(node.each_type.to_a)
          next unless NAMED_TYPES.any? { |kind| node.is_a?(kind) }

          location = node.location[:name]
          first = location.start_pos - PREFIX.length
          last = location.end_pos - PREFIX.length
          return [[], "type name outside signature text"] unless first >= 0 && last <= text.length && text[first...last] == location.source

          references << {"name" => location.source,
                         "start_offset" => text[0...first].bytesize, "end_offset" => text[0...last].bytesize}
        end
        [references.uniq.sort_by { |reference| reference.fetch("start_offset") }, nil]
      rescue RBS::ParsingError
        [[], "signature is not supported RBS syntax; text retained literally"]
      end

      def resolve(scope, owner, name)
        names = if name.start_with?("::")
          [name.delete_prefix("::")]
        else
          parts = owner.delete_prefix("::").split("::")
          parts.length.downto(0).map { |length| (parts.first(length) + [name]).join("::") }
        end
        local = lookup(scope, names)
        return local unless local.empty?

        @scopes.fetch(scope).fetch("references").uniq.sort.flat_map { |dependency| lookup(dependency, names) }
      end

      def lookup(scope, names)
        index = @indexes.fetch(scope)
        name = names.find { |candidate| index.key?(candidate) }
        name ? index.fetch(name).map { |row| [scope, row] } : []
      end

      def target(scope, row)
        {"scope" => scope, "declaration_id" => row.fetch("id"), "path" => row.fetch("page"),
         "anchor" => row.fetch("anchor"), "span" => row.fetch("span")}
      end
    end
    private_constant :TypeReferences
  end
end
