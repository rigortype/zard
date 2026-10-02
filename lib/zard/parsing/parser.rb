# frozen_string_literal: true

require "prism"

module Zard
  module Parsing
    class Parser
      def self.call(source, path:)
        new(source, path).call
      end

      def initialize(source, path)
        @source = source
        @path = path
      end

      def call
        result = Prism.parse(@source)
        diagnostics = result.errors.map do |error|
          diagnostic("ruby.syntax", :error, error.message, span(error.location))
        end

        declarations = DeclarationCollector.new(
          @source,
          @path,
          result.comments,
          diagnostics
        ).call(result.value)

        Model::V1::Document.new(
          path: @path,
          declarations: declarations.freeze,
          diagnostics: diagnostics.freeze
        )
      end

      private

      def diagnostic(code, severity, message, location)
        Model::V1::Diagnostic.new(code: code, severity: severity, message: message, span: location)
      end

      def span(location)
        Model::V1::SourceSpan.new(
          path: @path,
          start_line: location.start_line,
          start_column: location.start_column,
          end_line: location.end_line,
          end_column: location.end_column,
          start_offset: location.start_offset,
          end_offset: location.end_offset
        )
      end
    end

    class DeclarationCollector < Prism::Visitor
      def initialize(source, path, comments, diagnostics)
        @source = source
        @path = path
        @comments = comments.select { |comment| standalone?(comment) }
        @diagnostics = diagnostics
        @declarations = []
        @namespace = []
        @singleton_depth = 0
      end

      def call(program)
        program.accept(self)
        @declarations.freeze
      end

      def visit_module_node(node)
        within_namespace(node.constant_path.location.slice) { node.body&.accept(self) }
      end

      def visit_class_node(node)
        within_namespace(node.constant_path.location.slice) { node.body&.accept(self) }
      end

      def visit_singleton_class_node(node)
        @singleton_depth += 1
        node.body&.accept(self)
      ensure
        @singleton_depth -= 1
      end

      def visit_def_node(node)
        comments = comment_block_for(node.location.start_line)
        parsed = CommentBlockParser.new(@path, comments, @diagnostics).call

        @declarations << Model::V1::Declaration.new(
          kind: singleton_method?(node) ? :singleton_method : :instance_method,
          name: node.name.to_s,
          namespace: @namespace.empty? ? nil : @namespace.join("::"),
          parameters: parameter_names(node.parameters).freeze,
          span: span(node.location),
          comment_span: comment_span(comments),
          documentation: parsed.fetch(:documentation).freeze,
          contracts: parsed.fetch(:contracts).freeze
        )

        node.body&.accept(self)
      end

      private

      def within_namespace(name)
        previous_namespace = @namespace
        @namespace = name.start_with?("::") ? [] : @namespace.dup
        parts = name.sub(/\A::/, "").split("::")
        @namespace.concat(parts)
        yield
      ensure
        @namespace = previous_namespace
      end

      def singleton_method?(node)
        !node.receiver.nil? || @singleton_depth.positive?
      end

      def parameter_names(parameters)
        return [] unless parameters

        names = []
        names.concat(parameters.requireds.map { |parameter| parameter.name.to_s })
        names.concat(parameters.optionals.map { |parameter| parameter.name.to_s })
        names << prefixed_name("*", parameters.rest) if parameters.rest
        names.concat(parameters.posts.map { |parameter| parameter.name.to_s })
        names.concat(parameters.keywords.map { |parameter| "#{parameter.name}:" })
        names << prefixed_name("**", parameters.keyword_rest) if parameters.keyword_rest
        names << prefixed_name("&", parameters.block) if parameters.block
        names
      end

      def prefixed_name(prefix, parameter)
        return parameter.location.slice unless parameter.respond_to?(:name)

        parameter.name ? "#{prefix}#{parameter.name}" : prefix
      end

      def standalone?(comment)
        offset = comment.location.start_offset
        line_start = offset.zero? ? 0 : (@source.b.rindex("\n", offset - 1) || -1) + 1
        prefix = @source.byteslice(line_start, offset - line_start)
        prefix.match?(/\A[\t ]*\z/)
      end

      def comment_block_for(declaration_line)
        expected_line = declaration_line - 1
        block = []

        @comments.reverse_each do |comment|
          next if comment.location.end_line > expected_line
          break if comment.location.end_line < expected_line

          block << comment
          expected_line = comment.location.start_line - 1
        end

        block.reverse
      end

      def comment_span(comments)
        return nil if comments.empty?

        first = comments.first.location
        last = comments.last.location
        Model::V1::SourceSpan.new(
          path: @path,
          start_line: first.start_line,
          start_column: first.start_column,
          end_line: last.end_line,
          end_column: last.end_column,
          start_offset: first.start_offset,
          end_offset: last.end_offset
        )
      end

      def span(location)
        Model::V1::SourceSpan.new(
          path: @path,
          start_line: location.start_line,
          start_column: location.start_column,
          end_line: location.end_line,
          end_column: location.end_column,
          start_offset: location.start_offset,
          end_offset: location.end_offset
        )
      end
    end

    class CommentBlockParser
      def initialize(path, comments, diagnostics)
        @path = path
        @comments = comments
        @diagnostics = diagnostics
      end

      def call
        documentation = []
        contracts = []
        seen_non_extrbs_annotation = false

        @comments.each do |comment|
          raw = comment.location.slice
          body = raw.sub(/\A#\s*/, "")

          if body.match?(/\A@extrbs(?:\s|\z)/) && !raw.start_with?("# @extrbs")
            add_diagnostic(
              "extrbs.noncanonical-spacing",
              :warning,
              "Write @extrbs as '# @extrbs' with one space.",
              comment.location
            )
          end

          if (payload = contract_payload(body, "@extrbs"))
            if seen_non_extrbs_annotation
              add_diagnostic(
                "extrbs.not-first",
                :warning,
                "Place @extrbs before the other annotations in this comment block.",
                comment.location
              )
            end
            contracts << contract(:extrbs, payload, raw, comment.location)
          elsif (payload = contract_payload(body, "@rbs"))
            contracts << contract(:rbs, payload, raw, comment.location)
            seen_non_extrbs_annotation = true
          elsif raw.start_with?("#:")
            contracts << contract(:rbs, raw.delete_prefix("#:").strip, raw, comment.location)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@param(?:\s|\z)/)
            documentation << parse_named_tag(body, raw, comment.location, :param, "@param")
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@yieldparam(?:\s|\z)/)
            documentation << parse_named_tag(body, raw, comment.location, :yieldparam, "@yieldparam")
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@option(?:\s|\z)/)
            documentation << parse_option(body, raw, comment.location)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@raise(?:\s|\z)/)
            documentation << parse_named_tag(body, raw, comment.location, :raise, "@raise")
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@return(?:\s|\z)/)
            documentation << parse_nameless_tag(body, raw, comment.location, :return, "@return")
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@yieldreturn(?:\s|\z)/)
            documentation << parse_nameless_tag(body, raw, comment.location, :yieldreturn, "@yieldreturn")
            seen_non_extrbs_annotation = true
          elsif body.start_with?("@")
            documentation << raw_tag(body, raw, comment.location)
            seen_non_extrbs_annotation = true
          elsif !body.empty?
            documentation << documentation_tag(:text, nil, nil, body, raw, comment.location)
          end
        end

        {documentation: documentation, contracts: contracts}
      end

      private

      def contract_payload(body, tag)
        match = body.match(/\A#{Regexp.escape(tag)}(?:\s+(.*)|\z)/)
        match && match[1].to_s
      end

      def contract(channel, payload, raw, location)
        Model::V1::Contract.new(
          channel: channel,
          payload: payload,
          span: span(location),
          raw: raw
        )
      end

      def parse_named_tag(body, raw, location, name, prefix)
        rest = body.delete_prefix(prefix).strip
        head, marker, description = rest.partition(" — ")

        if marker.empty?
          yard_like(raw, location)
          return raw_tag(body, raw, location)
        end

        subject, claim, valid = parse_named_head(head)
        unless valid
          yard_like(raw, location)
          return raw_tag(body, raw, location)
        end

        documentation_tag(name, subject, claim, description, raw, location)
      end

      def parse_option(body, raw, location)
        rest = body.delete_prefix("@option").strip
        head, marker, description = rest.partition(" — ")
        owner, option_head = head.split(/\s+/, 2)
        subject, claim, valid = parse_named_head(option_head.to_s)

        if marker.empty? || !owner || !valid
          yard_like(raw, location)
          return raw_tag(body, raw, location)
        end

        documentation_tag(:option, subject, claim, description, raw, location, owner: owner)
      end

      def parse_nameless_tag(body, raw, location, name, prefix)
        rest = body.delete_prefix(prefix).strip

        if rest.start_with?("—")
          add_diagnostic(
            "documentation.redundant-marker",
            :warning,
            "Remove the redundant em dash from #{prefix} without a type claim.",
            location
          )
          return documentation_tag(name, nil, nil, rest.delete_prefix("—").strip, raw, location)
        end

        if rest.start_with?("[")
          claim, remainder = bracketed_claim(rest)
          unless claim && remainder.start_with?(" — ")
            yard_like(raw, location)
            return raw_tag(body, raw, location)
          end

          return documentation_tag(name, nil, claim, remainder.delete_prefix(" — "), raw, location)
        end

        documentation_tag(name, nil, nil, rest, raw, location)
      end

      def parse_named_head(head)
        subject, remainder = head.split(/\s+/, 2)
        return [nil, nil, false] unless subject
        return [subject, nil, true] unless remainder

        claim, trailing = bracketed_claim(remainder)
        return [subject, claim, true] if claim && trailing.empty?

        [subject, nil, false]
      end

      def bracketed_claim(text)
        return [nil, text] unless text.start_with?("[")

        depth = 0
        text.each_char.with_index do |character, index|
          depth += 1 if character == "["
          depth -= 1 if character == "]"
          next unless depth.zero?

          return [text[1...index], text[(index + 1)..]]
        end

        [nil, text]
      end

      def yard_like(raw, location)
        add_diagnostic(
          "documentation.yard-like",
          :warning,
          "This tag is preserved as raw text because it does not use the ZARD em dash marker.",
          location
        )
      end

      def raw_tag(body, raw, location)
        documentation_tag(:raw, nil, nil, body, raw, location)
      end

      def documentation_tag(name, subject, claim, description, raw, location, owner: nil)
        Model::V1::DocumentationTag.new(
          name: name,
          owner: owner,
          subject: subject,
          claim: claim,
          description: description,
          span: span(location),
          raw: raw
        )
      end

      def add_diagnostic(code, severity, message, location)
        @diagnostics << Model::V1::Diagnostic.new(
          code: code,
          severity: severity,
          message: message,
          span: span(location)
        )
      end

      def span(location)
        Model::V1::SourceSpan.new(
          path: @path,
          start_line: location.start_line,
          start_column: location.start_column,
          end_line: location.end_line,
          end_column: location.end_column,
          start_offset: location.start_offset,
          end_offset: location.end_offset
        )
      end
    end
  end
end
