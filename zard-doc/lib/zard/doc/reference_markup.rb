# frozen_string_literal: true

module Zard
  module Doc
    class ReferenceMarkup
      HTML_OR_AUTOLINK = /\A<(?:[A-Za-z][A-Za-z0-9+.-]{1,31}:[^<>\s]*|[^<>\s]+@[^<>\s]+|\/[A-Za-z][A-Za-z0-9-]*\s*|[A-Za-z][A-Za-z0-9-]*(?:\s+[A-Za-z_:][A-Za-z0-9_.:-]*(?:\s*=\s*(?:[^\s"'=<>`]+|'[^']*'|"[^"]*"))?)*\s*\/?|!--.*?--|![A-Z]+(?:\s+[^<>]*)?|\?.*?\?)>/m

      def self.rewrite(text, &reference)
        new(reference).rewrite(text)
      end

      def self.code_label?(text)
        text.start_with?("`") && code_end(text, 0) == text.length
      end

      def self.code_end(text, position)
        delimiter = text[position..].match(/\A`+/)[0]
        closing = text.match(/(?<!`)#{Regexp.escape(delimiter)}(?!`)/, position + delimiter.length)
        closing&.end(0)
      end

      def initialize(reference)
        @reference = reference
      end

      def rewrite(text)
        segments = []
        prose = +""
        fence = nil
        definition = false
        definition_destination = false
        definition_title = nil
        list_indentations = []
        previous_quotes = 0
        @reference_labels = {}
        text.each_line do |line|
          if fence
            content = fence_content(line, fence)
            if content
              segments << [false, line]
              delimiter = fence[:delimiter]
              closing = content.match(/\A {0,3}(`{3,}|~{3,})([^\n]*)/)
              fence = nil if closing && closing[1][0] == delimiter[0] && closing[1].length >= delimiter.length && closing[2].strip.empty?
              next
            end
            fence = nil
          end
          if definition_title
            segments << [false, line]
            definition_title = nil if title_end(line, definition_title) || line.strip.empty?
            next
          end
          prefix = line[/\A(?: {0,3}(?:> ?|(?:[-+*]|\d+[.)])(?: {1,4}(?! )| (?= {4})|\t)))+/].to_s
          content = line.delete_prefix(prefix)
          quotes = prefix.count(">")
          quote_content = line.sub(/\A(?: {0,3}> ?)+/, "")
          indentation = columns(quote_content[/\A[ \t]*/])
          list_start = prefix.match?(/[-+*]|\d+[.)]/)
          list_indentations.clear if quotes != previous_quotes
          if list_start
            list_indentations.pop while list_indentations.last && list_indentations.last > indentation
            list_indentations << columns(prefix.gsub(/ {0,3}> ?/, ""))
          elsif !line.strip.empty?
            list_indentations.pop while list_indentations.last && list_indentations.last > indentation
          end
          list_indentation = list_indentations.last
          content = dedent(quote_content, list_indentation) if !list_start && list_indentation
          setext = content.match?(/\A {0,3}(?:=+|-+)[ \t]*\r?\n?\z/)
          block_start = setext || list_start || quotes != previous_quotes || content.match?(/\A {0,3}(?:\#{1,6}(?:[ \t]|$)|(?:[-*_][ \t]*){3,}$)/)
          if block_start
            segments << [true, prose.dup]
            prose.clear
          end
          previous_quotes = quotes
          marker = content.match(/\A {0,3}(`{3,}|~{3,})([^\n]*)/)
          code_indentation = list_start ? columns(content[/\A[ \t]*/]) : indentation - (list_indentation || 0)
          indented = code_indentation >= 4 && prose.empty?
          reference_definition = content.match(/\A {0,3}\[([^\n]+)\]:/)
          if (definition && (definition_destination || content.match?(/\A[ \t]+\S/) || content.match?(/\A {0,3}["'(]/))) || reference_definition || line.strip.empty? || indented || (marker && (marker[1][0] != "`" || !marker[2].include?("`")))
            segments << [true, prose.dup]
            prose.clear
            segments << [false, line]
            definition = !!reference_definition || (definition && !line.strip.empty?)
            definition_destination = !!(reference_definition && content[reference_definition.end(0)..].strip.empty?)
            definition_title = open_title(reference_definition ? content[reference_definition.end(0)..] : content) if definition
            @reference_labels[normalize_label(reference_definition[1])] = true if reference_definition
            if marker
              fence = {delimiter: marker[1], quotes: quotes, indentation: list_indentation}
            end
          else
            definition = false
            definition_destination = false
            prose << line
          end
          if setext || content.match?(/\A {0,3}\#{1,6}(?:[ \t]|$)/)
            segments << [true, prose.dup]
            prose.clear
          end
        end
        segments << [true, prose]
        segments.map { |rewrite, source| rewrite ? rewrite_inline(source) : source }.join
      end

      private

      def rewrite_inline(text)
        output = +""
        position = 0
        while position < text.length
          if text[position] == "\\"
            output << text[position, 2]
            position += 2
          elsif text[position] == "`"
            ending = self.class.code_end(text, position) || (position + text[position..].match(/\A`+/)[0].length)
            output << text[position...ending]
            position = ending
          elsif text[position] == "!" && text[position + 1] == "[" && (ending = bracket_end(text, position + 1))
            ending = link_end(text, ending) || ending
            output << text[position...ending]
            position = ending
          elsif text[position] == "[" && (ending = bracket_end(text, position))
            body = text[(position + 1)...(ending - 1)]
            if (link_ending = link_end(text, ending))
              destination = text[(ending + 1)...(link_ending - 1)]
              value = (text[ending] == "(") ? destination.match(/\A([mc]):([^\s]+)\z/) : nil
              replacement = value && @reference.call(value[1], decode(value[2]), body)
              output << (replacement || text[position...link_ending])
              position = link_ending
            else
              if @reference_labels.key?(normalize_label(body))
                output << text[position...ending]
                position = ending
                next
              end
              rd = body.start_with?("[") && body.end_with?("]")
              body = body[1...-1].strip if rd
              value = body.match(/\A([mc]):([^\s]+)\z/)
              if value
                target = decode(value[2])
                output << (@reference.call(value[1], target, nil) || text[position...ending])
                position = ending
              elsif rd
                output << text[position...ending]
                position = ending
              else
                output << text[position]
                position += 1
              end
            end
          elsif text[position, 2] == "[["
            output << "[["
            position += 2
          elsif text[position] == "<" && (html = text[position..].match(HTML_OR_AUTOLINK))
            output << html[0]
            position += html[0].length
          else
            output << text[position]
            position += 1
          end
        end
        output
      end

      def decode(target)
        target.gsub(/\\([\\\[\]])/, '\1')
      end

      def columns(text)
        text.each_char.reduce(0) { |column, character| (character == "\t") ? column + 4 - column % 4 : column + 1 }
      end

      def dedent(text, indentation)
        whitespace = text[/\A[ \t]*/]
        " " * [columns(whitespace) - indentation, 0].max + text.delete_prefix(whitespace)
      end

      def open_title(text)
        opening = text.match(/(?:\A|[ \t])(["'(])/)
        return unless opening

        delimiter = (opening[1] == "(") ? ")" : opening[1]
        delimiter unless title_end(text[opening.end(0)..], delimiter)
      end

      def title_end(text, delimiter)
        position = 0
        while position < text.length
          return position + 1 if text[position] == delimiter

          position += (text[position] == "\\") ? 2 : 1
        end
        nil
      end

      def fence_content(line, fence)
        content = line
        fence[:quotes].times do
          quote = content[/\A {0,3}> ?/]
          return unless quote

          content = content.delete_prefix(quote)
        end
        indentation = fence[:indentation]
        return content unless indentation
        return if !content.strip.empty? && columns(content[/\A[ \t]*/]) < indentation

        dedent(content, indentation)
      end

      def normalize_label(label)
        label.strip.gsub(/\s+/, " ").downcase
      end

      def bracket_end(text, position)
        depth = 0
        while position < text.length
          case text[position]
          when "\\"
            position += 2
            next
          when "`"
            ending = self.class.code_end(text, position) || (position + text[position..].match(/\A`+/)[0].length)
            position = ending
            next
          when "["
            depth += 1
          when "]"
            depth -= 1
            return position + 1 if depth.zero?
          end
          position += 1
        end
        nil
      end

      def link_end(text, position)
        return bracket_end(text, position) if text[position] == "["
        return unless text[position] == "("

        depth = 0
        quote = nil
        angle = false
        while position < text.length
          if text[position] == "\\"
            position += 2
            next
          end
          if quote
            quote = nil if text[position] == quote
          elsif angle
            angle = false if text[position] == ">"
          elsif ["\"", "'"].include?(text[position]) && text[position - 1].match?(/\s/)
            quote = text[position]
          elsif text[position] == "<"
            angle = true
          else
            case text[position]
            when "("
              depth += 1
            when ")"
              depth -= 1
              return position + 1 if depth.zero?
            end
          end
          position += 1
        end
        nil
      end
    end
  end
end
