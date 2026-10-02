# frozen_string_literal: true

require "optparse"
require "zard/doc"

module Zard
  module Doc
    class CLI
      SEVERITY_RANK = {error: 2, warning: 1, info: 0}.freeze

      def self.run(argv, stdout: $stdout, stderr: $stderr)
        new(argv, stdout, stderr).run
      end

      def initialize(argv, stdout, stderr)
        @argv = argv.dup
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

        paths.each do |path|
          document = Zard.parse(File.read(path), path: path)
          document.diagnostics.each do |diagnostic|
            @stdout.puts format_diagnostic(diagnostic)
            failed ||= failing?(diagnostic)
          end
        rescue SystemCallError => error
          @stderr.puts "#{path}: #{error.message}"
          return 2
        end

        failed ? 1 : 0
      end

      def render(paths)
        documents = paths.map { |path| Zard.parse(File.read(path), path: path) }
        diagnostics = documents.flat_map(&:diagnostics)
        diagnostics.each { |diagnostic| @stderr.puts format_diagnostic(diagnostic) }
        return 1 if diagnostics.any? { |diagnostic| diagnostic.severity == :error }

        markdown = documents.map { |document| Zard::Doc.render(document) }.reject(&:empty?).join("\n")
        @stdout.print markdown
        0
      rescue SystemCallError => error
        @stderr.puts error.message
        2
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
