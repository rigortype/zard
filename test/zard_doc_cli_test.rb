# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tempfile"
require "tmpdir"
require "zard/doc/cli"

class ZardDocCLITest < Minitest::Test
  def test_lint_reports_warnings_without_failing_by_default
    with_source("# @param value [String] Text.\ndef call(value) = value\n") do |path|
      status, stdout, stderr = run_cli("lint", path)

      assert_equal 0, status
      assert_includes stdout, "warning documentation.yard-like"
      assert_empty stderr
    end
  end

  def test_lint_can_fail_on_warnings
    with_source("# @return — Value.\ndef call = 1\n") do |path|
      status, stdout, stderr = run_cli("lint", "--fail-on", "warning", path)

      assert_equal 1, status
      assert_includes stdout, "warning documentation.redundant-marker"
      assert_empty stderr
    end
  end

  def test_lint_fails_on_ruby_syntax_errors
    with_source("def call(\n") do |path|
      status, stdout, stderr = run_cli("lint", path)

      assert_equal 1, status
      assert_includes stdout, "error ruby.syntax"
      assert_empty stderr
    end
  end

  def test_lint_rejects_a_missing_file
    status, stdout, stderr = run_cli("lint", "missing.rb")

    assert_equal 2, status
    assert_empty stdout
    assert_includes stderr, "missing.rb:"
  end

  def test_render_writes_markdown
    with_source("# @return Value.\ndef call = 1\n") do |path|
      status, stdout, stderr = run_cli("render", path)

      assert_equal 0, status
      assert_includes stdout, "## `call()`"
      assert_includes stdout, "### Returns\n\nValue."
      assert_empty stderr
    end
  end

  def test_render_reports_syntax_errors_without_markdown
    with_source("# @return Value.\ndef call(\n") do |path|
      status, stdout, stderr = run_cli("render", path)

      assert_equal 1, status
      assert_empty stdout
      assert_includes stderr, "error ruby.syntax"
    end
  end

  def test_lint_discovers_ruby_files_in_directories
    Dir.mktmpdir("zard-doc") do |directory|
      nested = File.join(directory, "nested")
      Dir.mkdir(nested)
      File.write(File.join(directory, "clean.rb"), "def clean = nil\n")
      File.write(File.join(nested, "warning.rb"), "# @return — Value.\ndef call = 1\n")
      File.write(File.join(nested, "ignored.txt"), "# @return — Value.\n")

      status, stdout, stderr = run_cli("lint", "--fail-on", "warning", directory)

      assert_equal 1, status
      assert_includes stdout, "warning.rb:1:1: warning documentation.redundant-marker"
      refute_includes stdout, "ignored.txt"
      assert_empty stderr
    end
  end

  def test_render_deduplicates_and_sorts_discovered_files
    Dir.mktmpdir("zard-doc") do |directory|
      first = File.join(directory, "a.rb")
      second = File.join(directory, "b.rb")
      File.write(first, "# @return A.\ndef a = 1\n")
      File.write(second, "# @return B.\ndef b = 2\n")

      status, stdout, stderr = run_cli("render", second, directory)

      assert_equal 0, status
      assert_operator stdout.index("## `a()`"), :<, stdout.index("## `b()`")
      assert_equal 1, stdout.scan("## `b()`").length
      assert_empty stderr
    end
  end

  def test_lint_reports_all_readable_files_before_returning_an_input_error
    with_source("# @return — Value.\ndef call = 1\n") do |path|
      status, stdout, stderr = run_cli("lint", "missing.rb", path)

      assert_equal 2, status
      assert_includes stdout, "warning documentation.redundant-marker"
      assert_includes stderr, "missing.rb:"
    end
  end

  def test_render_does_not_emit_partial_markdown_after_an_input_error
    with_source("# @return Value.\ndef call = 1\n") do |path|
      status, stdout, stderr = run_cli("render", "missing.rb", path)

      assert_equal 2, status
      assert_empty stdout
      assert_includes stderr, "missing.rb:"
    end
  end

  def test_lint_reads_standard_input_from_a_dash
    status, stdout, stderr = run_cli("lint", "--fail-on", "warning", "-", stdin: "# @return — Value.\ndef call = 1\n")

    assert_equal 1, status
    assert_includes stdout, "-:1:1: warning documentation.redundant-marker"
    assert_empty stderr
  end

  def test_render_reads_standard_input_from_a_dash
    status, stdout, stderr = run_cli("render", "-", stdin: "# @return Value.\ndef call = 1\n")

    assert_equal 0, status
    assert_includes stdout, "## `call()`"
    assert_empty stderr
  end

  private

  def run_cli(*arguments, stdin: "")
    input = StringIO.new(stdin)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Zard::Doc::CLI.run(arguments, stdin: input, stdout: stdout, stderr: stderr)
    [status, stdout.string, stderr.string]
  end

  def with_source(source)
    Tempfile.create(["zard-doc", ".rb"]) do |file|
      file.write(source)
      file.close
      yield file.path
    end
  end
end
