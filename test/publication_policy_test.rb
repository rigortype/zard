# frozen_string_literal: true

require "test_helper"
require "zard/doc/cli"
require "tmpdir"
require "fileutils"
require "stringio"
require "json"
require "yaml"

class PublicationPolicyTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/publication", __dir__)

  def test_canonical_markers_preserve_raw_provenance_and_reject_conflicts
    source = "# @api internal — **Implementation**.\n# Continued explanation.\ndef hidden; end\n"
    document = Zard.parse(source, path: "api.rb")
    tag = document.declarations.first.documentation.first
    assert_equal [:api, "internal", nil], [tag.name, tag.subject, tag.claim]
    assert_equal "**Implementation**.\nContinued explanation.", tag.description
    assert_equal source.lines.first(2).join.chomp, tag.raw
    assert_equal [1, 2], [tag.span.start_line, tag.span.end_line]
    ["@api internal", "@internal", "@private"].each do |marker|
      raw = Zard.parse("# #{marker}\ndef compatible; end\n", path: "api.rb")
      assert_equal :raw, raw.declarations.first.documentation.first.name
    end
    ["@api unstable — Invalid.", "@api public [String] — Invalid."].each do |marker|
      invalid = Zard.parse("# #{marker}\ndef invalid; end\n", path: "api.rb")
      assert invalid.diagnostics.any? { |item| item.code == "documentation.invalid-api" && item.severity == :error }
    end
    conflicting = Zard.parse("# @api public — Public.\n# @api internal — Internal.\ndef conflict; end\n", path: "api.rb")
    assert conflicting.diagnostics.any? { |item| item.code == "documentation.conflicting-api" && item.severity == :error }
    assert_empty Zard::Doc.render(document)
  end

  def test_default_and_opt_in_policy_gate_every_export_destination
    with_fixture do |root, config|
      inclusive = export(config)
      rows = inclusive.fetch("scopes").first.fetch("declarations")
      assert_equal 2, inclusive.fetch("revision")
      assert rows.any? { |row| row["name"] == "private_hook" && row["visibility"] == "private" && row["publication"] == "public" }
      assert rows.any? { |row| row["name"] == "implementation" && row["visibility"] == "public" && row["publication"] == "internal" }
      assert_equal 2, rows.count { |row| row["display_name"] == "API#modern" }
      old = rows.find { |row| row["name"] == "old" }
      tag = old.fetch("documentation").find { |item| item["name"] == "deprecated" }
      assert_includes tag.fetch("description"), "**modern**"
      assert_includes tag.fetch("raw"), "# @deprecated"
      assert_equal "lib/api.rb", tag.fetch("span").fetch("path")
      assert_includes tag.fetch("rendered_description"), "`[m:API#modern]`"
      data = YAML.safe_load_file(config)
      data.delete("publication")
      File.write(config, data.to_yaml)
      selected = export(config)
      scope = selected.fetch("scopes").first
      public_rows = scope.fetch("declarations")
      assert public_rows.all? { |row| row["visibility"] == "public" && row["publication"] == "public" }
      assert public_rows.any? { |row| row["display_name"] == "HiddenBase#hook" }
      assert public_rows.any? { |row| row["display_name"] == "HiddenBase::Nested" }
      assert public_rows.any? { |row| row["display_name"] == "API#extension" }
      assert public_rows.any? { |row| row["name"] == "yard_compatibility" }
      refute public_rows.any? { |row| row["display_name"] == "InternalOnly" || row["display_name"] == "HiddenBase" }
      refute scope.fetch("pages").any? { |page| page["path"] == "example/InternalOnly.md" }
      api = public_rows.find { |row| row["display_name"] == "API" }
      assert_equal "unresolved", api.fetch("relationships").first.fetch("status")
      assert_empty api.fetch("relationships").first.fetch("targets")
      prose = api.fetch("documentation").first.fetch("rendered_description")
      assert_includes prose, "[m:HiddenBase#helper]"
      assert_includes prose, "[c:InternalOnly]"
      selected.fetch("links").each_value do |targets|
        targets.each { |target| assert public_rows.any? { |row| row["page"] == target["path"] && row["anchor"] == target["anchor"] } }
      end
      public_rows.each do |row|
        assert_equal rows.find { |previous| previous["id"] == row["id"] }.fetch("anchor"), row.fetch("anchor")
      end
    end
  end

  def test_axes_override_independently_and_empty_allowlists_omit_all
    with_fixture do |root, config|
      data = YAML.safe_load_file(config)
      data["scopes"]["example"]["publication"] = {"intent" => ["public"]}
      File.write(config, data.to_yaml)
      rows = export(config).fetch("scopes").first.fetch("declarations")
      assert rows.any? { |row| row["visibility"] == "private" }
      assert rows.all? { |row| row["publication"] == "public" }
      data["publication"]["visibility"] = []
      File.write(config, data.to_yaml)
      scope = export(config).fetch("scopes").first
      assert_empty scope.fetch("declarations")
      assert_empty scope.fetch("pages")
      data["publication"] = {"intent" => ["invalid"]}
      File.write(config, data.to_yaml)
      status, output, = run_cli(config, "json")
      assert_equal 2, status
      assert_empty output
    end
  end

  def test_regeneration_removes_excluded_managed_pages_but_keeps_members_and_guides
    with_fixture do |root, config|
      status, _, errors = run_cli(config, "markdown")
      assert_equal 0, status, errors
      excluded = File.join(root, "docs/api/example/InternalOnly.md")
      assert File.file?(excluded)
      guide = File.join(root, "docs/api/guide.md")
      File.write(guide, "Handwritten guide\n")
      data = YAML.safe_load_file(config)
      data.delete("publication")
      File.write(config, data.to_yaml)
      status, _, errors = run_cli(config, "markdown")
      assert_equal 0, status, errors
      refute File.exist?(excluded)
      assert_equal "Handwritten guide\n", File.read(guide)
      assert File.file?(File.join(root, "docs/api/example/HiddenBase.md"))
      refute_includes File.read(File.join(root, "docs/api/example/index.md")), "InternalOnly"
      api = File.read(File.join(root, "docs/api/example/API.md"))
      refute_includes api, "Ruby-public implementation API"
      refute_includes api, "Documented private integration point"
      assert_includes api, "### Deprecated"
      assert_includes api, "**modern**"
    end
  end

  private

  def with_fixture
    Dir.mktmpdir("zard-publication") do |root|
      FileUtils.cp_r(File.join(FIXTURE, "."), root)
      yield root, File.join(root, "zard-doc.yml")
    end
  end

  def export(config)
    status, output, errors = run_cli(config, "json")
    assert_equal 0, status, errors
    JSON.parse(output)
  end

  def run_cli(config, format)
    output = StringIO.new
    errors = StringIO.new
    status = Zard::Doc::CLI.run(["build", "--config", config, "--format", format], stdout: output, stderr: errors)
    [status, output.string, errors.string]
  end
end
