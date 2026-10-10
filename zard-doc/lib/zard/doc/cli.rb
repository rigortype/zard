# frozen_string_literal: true

require "optparse"
require "zard/doc"

module Zard
  module Doc
    class CLI
      SEVERITY_RANK = {error: 2, warning: 1, info: 0}.freeze

      def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr)
        new(argv, stdin, stdout, stderr).run
      end

      def initialize(argv, stdin, stdout, stderr)
        @argv = argv.dup
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
        @fail_on = :error
      end

      def run
        return help if @argv.first == "--help" || @argv.first == "-h"

        case @argv.shift
        when "lint"
          lint_command
        when "render"
          render_command
        else
          usage_error("Expected the lint or render command.")
        end
      rescue OptionParser::ParseError => error
        usage_error(error.message)
      end

      private

      def lint_command
        lint_option_parser.parse!(@argv)
        return usage_error("Pass at least one Ruby source file.") if @argv.empty?

        paths = source_paths(@argv)
        return usage_error("No Ruby source files were found.") if paths.empty?

        lint(paths)
      end

      def lint_option_parser
        OptionParser.new do |parser|
          parser.banner = usage
          parser.on("--fail-on LEVEL", %w[error warning], "Minimum severity that exits unsuccessfully") do |level|
            @fail_on = level.to_sym
          end
        end
      end

      def render_command
        OptionParser.new.parse!(@argv)
        return usage_error("Pass at least one Ruby source file.") if @argv.empty?

        paths = source_paths(@argv)
        return usage_error("No Ruby source files were found.") if paths.empty?

        render(paths)
      end

      def source_paths(inputs)
        inputs.flat_map do |input|
          File.directory?(input) ? Dir.glob(File.join(input, "**", "*.rb")).sort : input
        end.uniq.sort
      end

      def lint(paths)
        failed = false
        input_error = false

        paths.each do |path|
          source = read_source(path)
          unless source
            input_error = true
            next
          end

          document = Zard.parse(source, path: path)
          document.diagnostics.each do |diagnostic|
            @stdout.puts format_diagnostic(diagnostic)
            failed ||= failing?(diagnostic)
          end
        end

        return 2 if input_error

        failed ? 1 : 0
      end

      def render(paths)
        documents = paths.filter_map do |path|
          source = read_source(path)
          Zard.parse(source, path: path) if source
        end
        return 2 if documents.length != paths.length

        diagnostics = documents.flat_map(&:diagnostics)
        diagnostics.each { |diagnostic| @stderr.puts format_diagnostic(diagnostic) }
        return 1 if diagnostics.any? { |diagnostic| diagnostic.severity == :error }

        markdown = Renderer.render_documents(documents)
        @stdout.print markdown
        0
      end

      def read_source(path)
        return @stdin.read if path == "-"

        File.read(path)
      rescue SystemCallError => error
        @stderr.puts "#{path}: #{error.message}"
        nil
      end

      def failing?(diagnostic)
        SEVERITY_RANK.fetch(diagnostic.severity) >= SEVERITY_RANK.fetch(@fail_on)
      end

      def format_diagnostic(diagnostic)
        span = diagnostic.span
        "#{span.path}:#{span.start_line}:#{span.start_column + 1}: #{diagnostic.severity} #{diagnostic.code} #{diagnostic.message}"
      end

      def help
        @stdout.puts usage
        0
      end

      def usage_error(message)
        @stderr.puts message
        @stderr.puts usage
        2
      end

      def usage
        <<~USAGE.chomp
          Usage:
            zard-doc lint [--fail-on error|warning] PATH...
            zard-doc render PATH...
        USAGE
      end
    end
  end
end
