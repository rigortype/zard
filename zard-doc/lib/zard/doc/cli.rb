# frozen_string_literal: true

require "optparse"
require "zard/doc"
require "zard/doc/build"

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
        when "format"
          format_command
        when "build"
          build_command
        else
          usage_error("Expected the lint, render, format, or build command.")
        end
      rescue OptionParser::ParseError => error
        usage_error(error.message)
      end

      private

      def build_command
        config = nil
        layout = nil
        format = "markdown"
        scopes = []
        lens_root = nil
        rigor_command = nil
        lens_workers = 4
        lens_config = nil
        OptionParser.new do |parser|
          parser.on("--config FILE", "Read the documentation build configuration") { |value| config = value }
          parser.on("--layout LAYOUT", %w[namespace file], "Override page organization") { |value| layout = value }
          parser.on("--format FORMAT", %w[markdown json], "Write Markdown pages or export JSON to stdout") { |value| format = value }
          parser.on("--scope NAME", "Build a scope and its documentation dependencies (repeatable)") { |value| scopes << value }
          parser.on("--lens-root DIR", "Enrich JSON using experimental Rigor lens (requires zard-rigor)") { |value| lens_root = value }
          parser.on("--rigor-command FILE", "Rigor 0.4.3 executable (default: rigor)") { |value| rigor_command = value }
          parser.on("--lens-workers N", Integer, "Lens workers (default: 4)") { |value| lens_workers = value }
          parser.on("--lens-config FILE", "Rigor configuration, relative to lens root") { |value| lens_config = value }
        end.parse!(@argv)
        return usage_error("Pass --config FILE without positional arguments.") unless config && @argv.empty?

        return usage_error("--lens-root requires --format json.") if lens_root && format != "json"
        return usage_error("--rigor-command requires --lens-root.") if rigor_command && !lens_root
        return usage_error("--lens-config requires --lens-root.") if lens_config && !lens_root
        return usage_error("--lens-workers must be non-negative.") if lens_workers.negative?

        enricher = lens_enricher(lens_root, rigor_command || "rigor", lens_workers, lens_config) if lens_root
        builder = Build.new(config, layout: layout, scopes: scopes, format: format, stdout: @stdout, enricher: enricher)
        builder.run
      rescue BuildError => error
        @stderr.puts error.message
        error.status
      ensure
        builder&.diagnostics&.each { |diagnostic| @stderr.puts diagnostic }
      end

      def lens_enricher(root, command, workers, config)
        require "zard/rigor"
        adapter = Zard::Rigor::Lens.new(root: root, command: command, workers: workers, config: config)
        lambda do |data, base:|
          adapter.enrich(data, base: base)
        rescue Zard::Rigor::Error => error
          raise BuildError, error.message
        end
      rescue LoadError => error
        raise BuildError, "Install the optional zard-rigor gem to use --lens-root: #{error.message}"
      rescue SystemCallError => error
        raise BuildError, "Invalid lens project root: #{error.message}"
      end

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

      def format_command
        check = false
        write = false
        OptionParser.new do |parser|
          parser.on("--check", "Check whether formatting would change source") { check = true }
          parser.on("--write", "Write formatted source to files") { write = true }
        end.parse!(@argv)
        return usage_error("Choose either --check or --write.") if check && write
        return usage_error("Pass at least one Ruby source file.") if @argv.empty?

        paths = source_paths(@argv)
        return usage_error("No Ruby source files were found.") if paths.empty?
        return usage_error("Standard input cannot be used with --write.") if write && paths.include?("-")
        return usage_error("Pass one input for stdout, or use --check or --write.") if !check && !write && paths.length != 1

        results = paths.map do |path|
          source = read_source(path)
          return 2 unless source

          [path, Zard.format(source, path: path)]
        end
        results.each do |_, result|
          result.diagnostics.each { |diagnostic| @stderr.puts format_diagnostic(diagnostic) }
        end
        return 1 if results.any? { |_, result| result.diagnostics.any? { |diagnostic| diagnostic.severity == :error } }
        return (results.any? { |_, result| result.changed? }) ? 1 : 0 if check

        if write
          results.each do |path, result|
            File.binwrite(path, result.source) if result.changed?
          rescue SystemCallError => error
            @stderr.puts "#{path}: #{error.message}"
            return 2
          end
        else
          @stdout.print results.first[1].source
        end
        0
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
            zard-doc format [--check | --write] PATH...
            zard-doc build --config FILE [--scope NAME ...] [--layout namespace|file] [--format markdown|json]
              [--lens-root DIR [--rigor-command FILE] [--lens-workers N] [--lens-config FILE]]
        USAGE
      end
    end
  end
end
