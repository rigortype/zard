# frozen_string_literal: true

module Zard
  class FormatResult
    attr_reader :source, :document, :diagnostics

    def initialize(source:, document:, diagnostics:, changed:)
      @source = source.dup.freeze
      @document = document
      @diagnostics = diagnostics.freeze
      @changed = changed
      freeze
    end

    def changed?
      @changed
    end
  end

  module Formatting
    class Formatter
      def self.call(source, path:)
        new(source, path).call
      end

      def initialize(source, path)
        @source = source
        @path = path
      end

      def call
        unless @source.encoding.ascii_compatible?
          return encoding_error("format.unsupported-encoding", "Formatting requires UTF-8 source text.")
        end
        parsed = Prism.parse(@source.b)
        unless @source.dup.force_encoding(parsed.encoding).valid_encoding?
          return encoding_error("format.invalid-encoding", "Source bytes are invalid for the declared encoding.")
        end
        original = Zard.parse(@source, path: @path)
        if original.diagnostics.any? { |diagnostic| diagnostic.severity == :error }
          return result(@source, original)
        end
        unless parsed.encoding == Encoding::UTF_8
          diagnostic = format_diagnostic("format.unsupported-encoding", :error, "Formatting requires UTF-8 source text.", original.declarations.first&.span)
          return result(@source, original, [diagnostic])
        end

        output = @source.b.dup
        unsafe_lines = []
        blocks = original.declarations.filter_map(&:comment_span).uniq { |span| [span.start_offset, span.end_offset] }
        blocks.sort_by(&:start_offset).reverse_each do |span|
          start = line_start(span.start_offset)
          ending = (@source.b.index("\n", span.end_offset) || (@source.bytesize - 1)) + 1
          block = @source.byteslice(start, ending - start).dup.force_encoding(parsed.encoding)
          normalized = normalize(block, span, original)
          ordered = reorder(normalized, literal_lines(normalized))
          if ordered != normalized
            baseline = replace(output, start, block.bytesize, normalized)
            candidate = replace(output, start, block.bytesize, ordered)
            if snapshot(Zard.parse(baseline.force_encoding(@source.encoding), path: @path)) == snapshot(Zard.parse(candidate.force_encoding(@source.encoding), path: @path))
              normalized = ordered
            else
              unsafe_lines << span.start_line
            end
          end
          output = replace(output, start, block.bytesize, normalized)
        end
        output.force_encoding(@source.encoding)
        document = Zard.parse(output, path: @path)
        diagnostics = unsafe_lines.sort.map do |line|
          span = document.declarations.filter_map(&:comment_span).find { |item| item.start_line == line }
          format_diagnostic("format.unsafe-extrbs-order", :warning, "Leave @extrbs in place because moving it would change documentation or contract content.", span)
        end
        result(output, document, diagnostics)
      end

      private

      def result(source, document, diagnostics = [])
        FormatResult.new(source: source, document: document, diagnostics: document.diagnostics + diagnostics, changed: source.b != @source.b)
      end

      def encoding_error(code, message)
        diagnostic = format_diagnostic(code, :error, message, nil)
        document = Model::V1::Document.new(path: @path, declarations: [].freeze, diagnostics: [diagnostic].freeze)
        result(@source, document)
      end

      def line_start(offset)
        offset.zero? ? 0 : (@source.b.rindex("\n", offset - 1) || -1) + 1
      end

      def replace(source, start, length, replacement)
        source.byteslice(0, start).b + replacement.b + source.byteslice(start + length, source.bytesize).b
      end

      def normalize(block, span, document)
        literal = literal_lines(block)
        blocked = document.declarations.flat_map do |declaration|
          declaration.documentation.each_with_index.filter_map do |tag, index|
            next unless tag.name == :raw

            continuation = tag.raw.lines.drop(1).any? { |line| !line.sub(/\A[ \t]*# ?/, "").strip.empty? }
            example = index.positive? && declaration.documentation[index - 1].name == :example
            tag.span.start_line if continuation || example
          end
        end
        redundant = document.diagnostics.select { |diagnostic| diagnostic.code == "documentation.redundant-marker" }.map { |diagnostic| diagnostic.span.start_line }
        ambiguous = document.declarations.flat_map(&:documentation).select do |tag|
          %i[return yieldreturn].include?(tag.name) && tag.claim.nil? && tag.description.start_with?("[", "—")
        end.map { |tag| tag.span.start_line }
        block.lines.each_with_index.map do |line, index|
          number = span.start_line + index
          if literal.include?(index)
            line
          elsif !blocked.include?(number) && line.match?(/\A[ \t]*#[ \t]*@extrbs(?:[ \t]|\r?\n|\z)/)
            line.sub(/\A([ \t]*)#[ \t]*@extrbs/, '\1# @extrbs')
          elsif redundant.include?(number) && !ambiguous.include?(number)
            line.sub(/(@(?:return|yieldreturn)[ \t])— ?/, '\1')
          else
            line
          end
        end.join
      end

      def literal_lines(block)
        protected = []
        example = false
        fence = nil
        block.lines.each_with_index do |line, index|
          body = line.sub(/\A[ \t]*# ?/, "")
          content = fence ? body : body.sub(/\A@(?:example|note|deprecated|see)(?:[ \t]|\z)/, "")
          marker = content.match(/\A {0,3}(`{3,}|~{3,})([^\r\n]*)/)
          if fence
            protected << index
            fence = nil if marker && marker[1][0] == fence[0] && marker[1].length >= fence.length && marker[2].strip.empty?
            next
          end
          canonical = line.match?(/\A[ \t]*#(?: @|:)/)
          if canonical
            example = body.match?(/\A@example(?:[ \t]|\r?\n|\z)/)
          elsif example
            protected << index
          end
          if marker && (marker[1][0] != "`" || !marker[2].include?("`"))
            fence = marker[1]
            protected << index
          end
        end
        protected
      end

      def reorder(block, protected)
        lines = block.lines
        first = lines.index { |line| line.match?(/\A[ \t]*#(?: @|:)/) }
        return block unless first

        terminators = lines.map { |line| line[/\r?\n\z/].to_s }
        bodies = lines.map { |line| line.delete_suffix(line[/\r?\n\z/].to_s) }
        annotations = bodies.drop(first)
        extrbs, remaining = annotations.each_with_index.partition { |line, index| !protected.include?(first + index) && line.match?(/\A[ \t]*# @extrbs(?:[ \t]|\z)/) }
        (bodies.take(first) + (extrbs + remaining).map(&:first)).each_with_index.map { |line, index| line + terminators[index] }.join
      end

      def snapshot(document)
        document.declarations.map do |declaration|
          tags = declaration.documentation.map { |tag| [tag.name, tag.owner, tag.subject, tag.claim, tag.description] }
          contracts = declaration.contracts.map { |contract| [contract.channel, contract.payload, contract.note] }.sort_by(&:inspect)
          [declaration.kind, declaration.name, declaration.namespace, declaration.receiver, declaration.refinement, tags, contracts]
        end
      end

      def format_diagnostic(code, severity, message, span)
        span ||= Model::V1::SourceSpan.new(path: @path, start_line: 1, start_column: 0, end_line: 1, end_column: 0, start_offset: 0, end_offset: 0)
        Model::V1::Diagnostic.new(code: code, severity: severity, message: message, span: span)
      end
    end
  end
end
