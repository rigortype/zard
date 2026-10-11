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

  def test_render_links_see_references_across_files
    Dir.mktmpdir("zard-doc") do |directory|
      File.write(File.join(directory, "a.rb"), "class Foo\n  # Target.\n  def bar = nil\nend\n")
      File.write(File.join(directory, "b.rb"), "# @see Foo#bar Target\ndef call = nil\n")

      status, stdout, stderr = run_cli("render", directory)

      assert_equal 0, status
      assert_includes stdout, "- [Target](#zard-466f6f23626172)"
      assert_equal 1, stdout.scan('<a id="zard-466f6f23626172"></a>').length
      assert_empty stderr
    end
  end

  def test_render_keeps_ambiguous_see_references_as_text
    Dir.mktmpdir("zard-doc") do |directory|
      %w[a b].each do |name|
        File.write(File.join(directory, "#{name}.rb"), "class Foo\n  # Target.\n  def bar = nil\nend\n")
      end
      File.write(File.join(directory, "c.rb"), "# @see Foo#bar Target\ndef call = nil\n")

      status, stdout, stderr = run_cli("render", directory)

      assert_equal 0, status
      assert_includes stdout, "- Foo#bar Target"
      refute_includes stdout, "<a id="
      assert_empty stderr
    end
  end

  def test_render_links_explicit_bitclust_and_rd_forms_across_files
    Dir.mktmpdir("zard-doc") do |directory|
      File.write(File.join(directory, "a.rb"), "class Foo\n  # Target.\n  def bar = nil\nend\n")
      File.write(File.join(directory, "b.rb"), "# Read [m:Foo#bar].\n# @see [[m:Foo#bar]]\n# @see [Read a value](m:Foo#bar)\ndef call = nil\n")

      status, stdout, stderr = run_cli("render", directory)

      assert_equal 0, status
      assert_includes stdout, "Read [Foo#bar](#zard-466f6f23626172)."
      assert_includes stdout, "- [Foo#bar](#zard-466f6f23626172)"
      assert_includes stdout, "- [Read a value](#zard-466f6f23626172)"
      assert_equal 1, stdout.scan('<a id="zard-466f6f23626172"></a>').length
      assert_empty stderr
    end
  end

  def test_render_preserves_ambiguous_explicit_forms_across_files
    Dir.mktmpdir("zard-doc") do |directory|
      %w[a b].each do |name|
        File.write(File.join(directory, "#{name}.rb"), "class Foo\n  # Target.\n  def bar = nil\nend\n")
      end
      File.write(File.join(directory, "c.rb"), "# [m:Foo#bar] [[m:Foo#bar]]\n# @see [Read](m:Foo#bar)\ndef call = nil\n")

      status, stdout, stderr = run_cli("render", directory)

      assert_equal 0, status
      assert_includes stdout, "[m:Foo#bar] [[m:Foo#bar]]"
      assert_includes stdout, "- [Read](m:Foo#bar)"
      refute_includes stdout, "<a id="
      assert_empty stderr
    end
  end

  def test_format_prints_formatted_source_and_reads_standard_input
    source = "# @return — Value.\ndef call = nil\r\n"
    status, stdout, stderr = run_cli("format", "-", stdin: source)

    assert_equal 0, status
    assert_equal source.sub("@return —", "@return"), stdout
    assert_empty stderr
  end

  def test_format_check_reports_changes_without_writing
    with_source("# @return — Value.\ndef call = nil\n") do |path|
      original = File.binread(path)
      status, stdout, stderr = run_cli("format", "--check", path)

      assert_equal 1, status
      assert_empty stdout
      assert_empty stderr
      assert_equal original, File.binread(path)
    end
  end

  def test_format_write_discovers_files_and_is_idempotent
    Dir.mktmpdir("zard-format") do |directory|
      path = File.join(directory, "call.rb")
      File.binwrite(path, "# @return — Value.\r\ndef call = nil\r\n")
      ignored = File.join(directory, "ignored.txt")
      File.binwrite(ignored, "# @return — Literal.\n")
      status, stdout, stderr = run_cli("format", "--write", directory)

      assert_equal 0, status
      assert_empty stdout
      assert_empty stderr
      assert_equal "# @return Value.\r\ndef call = nil\r\n", File.binread(path)
      assert_equal "# @return — Literal.\n", File.binread(ignored).force_encoding(Encoding::UTF_8)
      assert_equal 0, run_cli("format", "--check", directory).first
      modified = File.mtime(path)
      assert_equal 0, run_cli("format", "--write", directory).first
      assert_equal modified, File.mtime(path)
    end
  end

  def test_format_leaves_ambiguous_documentation_and_reports_warnings
    source = "# @param value Text.\ndef call(value) = value\n"
    status, stdout, stderr = run_cli("format", "-", stdin: source)

    assert_equal 0, status
    assert_equal source, stdout
    assert_includes stderr, "warning documentation.yard-like"
  end

  def test_format_validates_all_sources_before_writing
    Dir.mktmpdir("zard-format") do |directory|
      good = File.join(directory, "a.rb")
      bad = File.join(directory, "b.rb")
      original = "# @return — Value.\ndef call = nil\n"
      File.write(good, original)
      File.write(bad, "def bad(\n")
      status, stdout, stderr = run_cli("format", "--write", directory)

      assert_equal 1, status
      assert_empty stdout
      assert_includes stderr, "error ruby.syntax"
      assert_equal original, File.read(good)
    end
  end

  def test_format_read_errors_do_not_write_other_files
    with_source("# @return — Value.\ndef call = nil\n") do |path|
      original = File.read(path)
      status, stdout, stderr = run_cli("format", "--write", path, "missing.rb")

      assert_equal 2, status
      assert_empty stdout
      assert_includes stderr, "missing.rb:"
      assert_equal original, File.read(path)
    end
  end

  def test_format_rejects_incompatible_modes_and_ambiguous_stdout
    [["--write", "-"], ["--write", "--check", "-"], ["a.rb", "b.rb"], []].each do |arguments|
      status, stdout, stderr = run_cli("format", *arguments)

      assert_equal 2, status
      assert_empty stdout
      assert_includes stderr, "Usage:"
    end
  end

  def test_format_reports_errors_without_printing_partial_output
    status, stdout, stderr = run_cli("format", "-", stdin: "# @return — Value.\ndef bad(\n")

    assert_equal 1, status
    assert_empty stdout
    assert_includes stderr, "error ruby.syntax"
  end

  def test_format_reports_invalid_encoding_without_raising
    status, stdout, stderr = run_cli("format", "-", stdin: "# text \xFF\ndef call = nil\n".b)

    assert_equal 1, status
    assert_empty stdout
    assert_includes stderr, "error format.invalid-encoding"
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
