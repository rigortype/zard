# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tempfile"
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

  private

  def run_cli(*arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Zard::Doc::CLI.run(arguments, stdout: stdout, stderr: stderr)
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
