# frozen_string_literal: true

require "rbs"

module Zard
  module Rigor
    # Finds named types in lens signature text and links them to documented declarations.
    #
    # Rigor spells contract types from resolved RBS definitions: class and interface names are
    # absolute, so a relative name there is a type variable. An inferred return is spelled by
    # Rigor's type printer with the full constant path and no leading `::`. Which documentation
    # scope declares a name is answered by zard-doc, never by spelling.
    class TypeReferences
      PREFIX = "class ZardSignature\n  def call: "
      NAMED_TYPES = [RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Interface].freeze

      def initialize(export, members, resolve_constant)
        @rows = export.fetch("scopes").to_h do |scope|
          [scope.fetch("name"), scope.fetch("declarations").to_h { |row| [row.fetch("id"), row] }]
        end
        @members = members.to_h { |member| [member.fetch("key"), member] }
        @resolve_constant = resolve_constant
        @parsed = {}
        @candidates = {}
      end

      def attach(binding)
        scope = binding.fetch("scope")
        references = []
        diagnostics = []
        binding.fetch("member_keys").each do |key|
          member = @members.fetch(key)
          label = "#{scope}:#{member.fetch("owner")}#{(member.fetch("scope") == "singleton") ? "." : "#"}#{member.fetch("name")}"
          member.fetch("overloads").each_with_index do |overload, index|
            text = overload["rbs"]
            next unless text

            inferred = overload.dig("return", "provenance") == "inferred"
            occurrences, notes = @parsed[[text, inferred]] ||= occurrences(text, inferred)
            diagnostics.concat(notes.map { |note| "#{label} overload #{index}: #{note}" })
            occurrences.each do |occurrence|
              reference, note = classify(scope, occurrence)
              references << reference.merge("member_key" => key, "overload" => index)
              diagnostics << "#{label} overload #{index}: #{note}" if note
            end
          end
        end
        binding.merge("type_references" => references, "type_reference_diagnostics" => diagnostics.uniq)
      end

      private

      def occurrences(text, inferred)
        _, _, declarations = RBS::Parser.parse_signature("#{PREFIX}#{text}\nend\n")
        method = declarations.first&.members&.first
        unless declarations.one? && declarations.first.members.one? && method.is_a?(RBS::AST::Members::MethodDefinition) && method.overloads.one?
          return [[], ["unsupported signature structure; text retained literally"]]
        end

        signature = method.overloads.first.method_type
        returns = signature.type.return_type.location
        nodes = signature.each_type.to_a
        signature.type_params.each do |parameter|
          nodes.concat([parameter.upper_bound_type, parameter.lower_bound_type, parameter.default_type].compact)
        end
        found = []
        notes = []
        until nodes.empty?
          node = nodes.shift
          nodes.concat(node.each_type.to_a)
          next unless NAMED_TYPES.any? { |kind| node.is_a?(kind) }

          location = node.location[:name]
          first = location.start_pos - PREFIX.length
          last = location.end_pos - PREFIX.length
          return [[], ["type name outside signature text; text retained literally"]] unless first >= 0 && last <= text.length && text[first...last] == location.source

          name = location.source
          unless name.start_with?("::")
            in_return = returns && location.start_pos >= returns.start_pos && location.end_pos <= returns.end_pos
            unless inferred && in_return
              notes << "unqualified type name #{name} in a contract signature; text retained literally" if name.include?("::")
              next
            end
          end
          found << {"name" => name, "constant" => "::#{name.delete_prefix("::")}",
                    "start_offset" => text[0...first].bytesize, "end_offset" => text[0...last].bytesize}
        end
        [found.uniq.sort_by { |occurrence| occurrence.fetch("start_offset") }, notes.uniq]
      rescue RBS::ParsingError
        [[], ["signature is not supported RBS syntax; text retained literally"]]
      end

      def classify(scope, occurrence)
        name = occurrence.fetch("name")
        candidates = @candidates[[scope, occurrence.fetch("constant")]] ||= @resolve_constant.call(scope, occurrence.fetch("constant"))
        linkable = candidates.select { |candidate| linkable?(candidate) }
        reference = occurrence.except("constant").merge(
          "candidates" => candidates.map { |candidate| candidate.slice("scope", "span") },
          "targets" => linkable.map { |candidate| target(candidate) }
        )
        if candidates.length > 1
          locations = candidates.map { |candidate| location(candidate) }.join(", ")
          return [reference.merge("status" => "ambiguous"), "ambiguous type reference #{name}; candidates: #{locations}"]
        end
        return [reference.merge("status" => "resolved"), nil] if linkable.one?
        return [reference.merge("status" => "unresolved", "reason" => "missing"), nil] if candidates.empty?

        candidate = candidates.first
        if candidate.fetch("declaration_id")
          [reference.merge("status" => "unresolved", "reason" => "not_class_or_module"),
            "type reference #{name} left literal; #{location(candidate)} is a #{candidate.fetch("kind")} declaration, not a class or module"]
        else
          [reference.merge("status" => "unresolved", "reason" => "unpublished"),
            "type reference #{name} left literal; its declaration at #{location(candidate)} is excluded from publication"]
        end
      end

      # A constant assigned from `Data.define`, `Struct.new`, `Class.new` or `Module.new` names a class or module.
      def linkable?(candidate)
        candidate.fetch("declaration_id") &&
          (%w[class module].include?(candidate.fetch("kind")) || (candidate.fetch("kind") == "constant" && candidate.fetch("container_builder")))
      end

      def target(candidate)
        row = @rows.fetch(candidate.fetch("scope")).fetch(candidate.fetch("declaration_id"))
        {"scope" => candidate.fetch("scope"), "declaration_id" => row.fetch("id"), "path" => row.fetch("page"),
         "anchor" => row.fetch("anchor"), "span" => candidate.fetch("span")}
      end

      def location(candidate)
        span = candidate.fetch("span")
        "#{candidate.fetch("scope")}:#{span.fetch("path")}:#{span.fetch("start_line")}"
      end
    end
    private_constant :TypeReferences
  end
end
