# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"
require "zard/doc"

class ReleaseIntegrationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  EXAMPLE = File.join(ROOT, "examples/catalog")
  EXECUTABLE = File.join(ROOT, "zard-doc/exe/zard-doc")

  def test_catalog_directory_renders_the_checked_in_expected_markdown
    status, stdout, stderr = run_cli("render", File.join(EXAMPLE, "lib"))

    assert_equal 0, status
    assert_equal File.read(File.join(EXAMPLE, "expected.md")), stdout
    assert_empty stderr
    refute_includes stdout, "internal_id"
    refute_includes stdout, "matches?"
    refute_includes stdout, "The stored value."
    assert_includes stdout, "Alias of `Catalog::Entry#label`."
  end

  def test_catalog_directory_lints_cleanly
    status, stdout, stderr = run_cli("lint", File.join(EXAMPLE, "lib"))

    assert_equal 0, status
    assert_empty stdout
    assert_empty stderr
  end

  def test_lint_warns_without_failing_and_strict_mode_fails
    with_source("# @param value [String] Text.\ndef call(value) = value\n") do |directory|
      status, stdout, stderr = run_cli("lint", directory)

      assert_equal 0, status
      assert_includes stdout, "warning documentation.yard-like"
      assert_empty stderr

      strict_status, strict_stdout, strict_stderr = run_cli("lint", "--fail-on", "warning", directory)
      assert_equal 1, strict_status
      assert_includes strict_stdout, "warning documentation.yard-like"
      assert_empty strict_stderr
    end
  end

  def test_lint_reports_syntax_errors
    with_source("def broken(\n") do |directory|
      status, stdout, stderr = run_cli("lint", directory)

      assert_equal 1, status
      assert_includes stdout, "error ruby.syntax"
      assert_empty stderr
    end
  end

  def test_lint_reports_unreadable_paths
    Dir.mktmpdir("zard-release") do |directory|
      missing_path = File.join(directory, "missing.rb")
      status, stdout, stderr = run_cli("lint", missing_path)

      assert_equal 2, status
      assert_empty stdout
      assert_includes stderr, "#{missing_path}:"
    end
  end

  def test_contract_payload_and_source_provenance_survive_model_parsing
    path = File.join(EXAMPLE, "lib/catalog/entry.rb")
    source = File.read(path)
    document = Zard.parse(source, path: path)
    declaration = document.declarations.find { |item| item.name == "read_name" }

    assert_empty document.diagnostics
    refute_nil declaration
    assert_equal [[:extrbs, "return: non-empty-string", nil],
      [:rbs, "path: String", nil],
      [:rbs, "return: String", "The stored value."]],
      declaration.contracts.map { |contract| [contract.channel, contract.payload, contract.note] }

    extrbs = declaration.contracts.first
    assert_equal [6, 6], [extrbs.span.start_line, extrbs.span.end_line]
    assert_equal "# @extrbs return: non-empty-string", extrbs.raw
    assert_equal path, extrbs.span.path
    assert_equal source.lines.fetch(5).index("#"), extrbs.span.start_column
    assert_equal extrbs.raw, source.byteslice(extrbs.span.start_offset...extrbs.span.end_offset)
    title = document.declarations.find { |item| item.name == "title" }
    assert_equal "label", title.alias_target
    assert_equal :public, title.visibility
    assert_equal :private, document.declarations.find { |item| item.name == "internal_id" }.visibility
    assert_equal :protected, document.declarations.find { |item| item.name == "matches?" }.visibility
  end

  def test_render_rejects_invalid_input_without_partial_markdown
    with_source("def broken(\n") do |directory|
      status, stdout, stderr = run_cli("render", File.join(EXAMPLE, "lib"), directory)

      assert_equal 1, status
      assert_empty stdout
      assert_includes stderr, "error ruby.syntax"
    end

    Dir.mktmpdir("zard-release") do |directory|
      status, stdout, stderr = run_cli("render", File.join(EXAMPLE, "lib"), File.join(directory, "missing.rb"))

      assert_equal 2, status
      assert_empty stdout
      assert_includes stderr, "missing.rb:"
    end
  end

  def test_render_reads_source_from_standard_input
    source = File.read(File.join(EXAMPLE, "lib/catalog.rb"))
    status, stdout, stderr = run_cli("render", "-", stdin: source)

    assert_equal 0, status
    assert_equal Zard::Doc.render(Zard.parse(source, path: "-")), stdout
    assert_empty stderr
  end

  private

  def run_cli(*arguments, stdin: "")
    command = [RbConfig.ruby, EXECUTABLE, *arguments]
    stdout, stderr, process = Open3.capture3(*command, chdir: ROOT, stdin_data: stdin)
    [process.exitstatus, stdout, stderr]
  end

  def with_source(source)
    Dir.mktmpdir("zard-release") do |directory|
      File.write(File.join(directory, "example.rb"), source)
      yield directory
    end
  end
end
