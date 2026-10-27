# frozen_string_literal: true

require "test_helper"
require "zard/doc/cli"
require "zard/rigor"
require "tmpdir"
require "fileutils"
require "stringio"

class RigorLensBoundariesTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/rigor_lens/boundaries", __dir__)

  def test_explicit_receiver_omission_does_not_borrow_another_singleton_signature
    with_project do |root, export|
      result = enrich(root, export)
      rows = result.fetch("scopes").first.fetch("declarations")
      explicit = rows.find { |row| row["receiver"] == "Target" }
      omitted = binding(result, explicit)
      assert_equal "unavailable", omitted.fetch("status")
      assert_equal "unsupported_declaration", omitted.fetch("reason")
      assert_equal({"kind" => "method", "reason" => "unsupported_kind"}, omitted.fetch("omission"))
      assert_nil omitted.fetch("site_key")
      assert_empty omitted.fetch("member_keys")
      singletons = rows.select { |row| row["receiver"] == "self" }
      assert_equal %w[Target.identity Boundary.identity], singletons.map { |row| row.fetch("display_name") }
      singletons.each do |row|
        matched = binding(result, row)
        assert_equal "matched", matched.fetch("status")
        assert_equal [[row.fetch("namespace"), "singleton", "identity"]], matched.fetch("member_keys").map { |key| JSON.parse(key) }
      end
      assert_equal 3, (singletons + [explicit]).map { |row| row.fetch("id") }.uniq.size
    end
  end

  def test_refinement_groups_keep_distinct_unavailable_definitions
    with_project do |root, export|
      result = enrich(root, export)
      rows = result.fetch("scopes").first.fetch("declarations")
      groups = rows.select { |row| row.fetch("kind") == "refinement" }
      methods = rows.select { |row| row["refinement"] }
      assert_equal %w[String Integer], methods.map { |row| row.fetch("refinement") }
      assert_equal 2, groups.size
      assert_equal 4, (groups + methods).map { |row| row.fetch("id") }.uniq.size
      (groups + methods).each do |row|
        unavailable = binding(result, row)
        assert_equal "unavailable", unavailable.fetch("status")
        assert_nil unavailable.fetch("site_key")
        assert_empty unavailable.fetch("member_keys")
      end
      assert groups.all? { |row| binding(result, row)["capability"] == "refinement" }
      assert methods.all? { |row| binding(result, row)["reason"] == "unmatched_declaration" }
    end
  end

  def test_preserves_reserved_extrbs_source_without_promoting_it_to_a_type_fact
    with_project do |root, export|
      original = export.fetch("scopes").first.fetch("declarations").find { |row| row.fetch("name") == "reserved" }
      result = enrich(root, export)
      row = result.fetch("scopes").first.fetch("declarations").find { |item| item.fetch("id") == original.fetch("id") }
      assert_equal original.fetch("contracts"), row.fetch("contracts")
      contract = row.fetch("contracts").first
      assert_equal "extrbs", contract.fetch("channel")
      assert_equal "(String value) -> Integer", contract.fetch("payload")
      assert_equal "# @extrbs (String value) -> Integer", contract.fetch("raw")
      source = File.binread(File.join(root, "lib/boundaries.rb"))
      span = contract.fetch("span")
      assert_equal contract.fetch("raw"), source.byteslice(span.fetch("start_offset")...span.fetch("end_offset"))
      member = result.fetch("lens").fetch("members").find { |item| item.fetch("name") == "reserved" }
      assert_equal "single_site", member.fetch("basis")
      value = member.fetch("overloads").first.fetch("return")
      assert_equal ["dynamic", "untyped", "inferred"], value.values_at("state", "type", "provenance")
    end
  end

  def test_retains_released_overloads_generics_block_and_extended_annotation_verbatim
    with_project do |root, export|
      members = enrich(root, export).fetch("lens").fetch("members")
      convert = members.find { |member| member.fetch("name") == "convert" }
      assert_equal ["(::String value) -> ::String", "(::Integer value) -> ::Integer"], convert.fetch("overloads").map { |overload| overload.fetch("rbs") }
      transform = members.find { |member| member.fetch("name") == "transform" }.fetch("overloads").first
      assert_equal "%a{rigor:v1:return: non-empty-string} [T] (T value) { (T) -> ::String } -> ::String", transform.fetch("rbs")
      assert_equal "T", transform.fetch("params").first.fetch("type").fetch("type")
      assert_equal true, transform.fetch("block").fetch("required")
      assert_equal "(T) -> ::String", transform.fetch("block").fetch("type").fetch("type")
      values = [transform.fetch("params").first.fetch("type"), transform.fetch("block").fetch("type"), transform.fetch("return")]
      assert values.all? { |value| value.values_at("provenance", "path") == ["sig", "sig/boundaries.rbs"] }
    end
  end

  def test_released_cli_reproduces_boundary_export_when_available
    command = ENV["ZARD_RIGOR_COMMAND"]
    skip "Set ZARD_RIGOR_COMMAND for released Rigor integration" unless command

    with_project do |root, export|
      actual = Zard::Rigor::Lens.new(root: root, command: command, workers: 0).enrich(export, base: root)
      assert_equal "0.4.5", actual.fetch("lens").fetch("producer").fetch("version")
      assert_equal enrich(root, export), actual
      astro_fixture = JSON.parse(File.read(File.expand_path("../zard-doc-astro/test/fixtures/lens-boundaries-export.json", __dir__)))
      assert_equal astro_fixture, actual
    end
  end

  private

  def binding(result, row)
    result.fetch("lens").fetch("bindings").find { |item| item.fetch("declaration_id") == row.fetch("id") }
  end

  def enrich(root, export)
    runner = lambda do |*arguments, **options|
      assert_equal ["rigor", "lens", "--format=json", "--workers", "4", "./lib/boundaries.rb"], arguments
      assert_equal File.realpath(root), options.fetch(:chdir)
      [File.read(File.join(FIXTURE, "expected.json")), "", Struct.new(:exitstatus).new(0)]
    end
    Zard::Rigor::Lens.new(root: root, runner: runner).enrich(export, base: root)
  end

  def with_project
    Dir.mktmpdir("zard-lens-boundaries-") do |root|
      %w[lib sig .rigor.yml].each { |path| FileUtils.cp_r(File.join(FIXTURE, path), root) }
      config = File.join(root, "zard-doc.yml")
      File.write(config, JSON.generate({docroot: "docs", scopes: {app: {destination: "app", sources: [{root: "lib"}]}}}))
      output = StringIO.new
      errors = StringIO.new
      assert_equal 0, Zard::Doc::CLI.run(["build", "--config", config, "--format", "json"], stdout: output, stderr: errors), errors.string
      yield root, JSON.parse(output.string)
    end
  end
end
