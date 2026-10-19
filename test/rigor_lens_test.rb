# frozen_string_literal: true

require "test_helper"
require "zard/doc/cli"
require "zard/rigor"
require "tmpdir"
require "fileutils"
require "stringio"

class RigorLensTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/rigor_lens", __dir__)

  def with_project
    Dir.mktmpdir("zard-lens-") do |root|
      FileUtils.cp_r(File.join(FIXTURE, "project", "."), root)
      config = File.join(root, "zard-doc.yml")
      File.write(config, JSON.generate({docroot: "docs", scopes: {app: {destination: "app",
                                                                        sources: [{root: ".", include: %w[lib/shop.rb lib/order.rb lib/util.rb]}]}}}))
      output = StringIO.new
      status = Zard::Doc::CLI.run(["build", "--config", config, "--format", "json"], stdout: output, stderr: StringIO.new)
      assert_equal 0, status
      yield root, JSON.parse(output.string)
    end
  end

  def fixture_document
    JSON.parse(File.read(File.join(FIXTURE, "expected.json")))
  end

  def adapter(root, document = fixture_document, status: 0, &before_return)
    runner = lambda do |*arguments, **options|
      assert_equal File.realpath(root), options.fetch(:chdir)
      assert_equal ["rigor", "lens", "--format=json", "--workers", "4"], arguments.first(5)
      before_return&.call
      [JSON.generate(document), "", Struct.new(:exitstatus).new(status)]
    end
    Zard::Rigor::Lens.new(root: root, runner: runner)
  end

  def test_joins_shared_span_attributes_and_keeps_member_facts_separate_from_source_prose
    with_project do |root, export|
      original = JSON.generate(export)
      result = adapter(root).enrich(export, base: root)
      assert_equal original, JSON.generate(export)
      lens = result.fetch("lens")
      assert_equal "rigor:v1", lens.fetch("adapter").fetch("grammar")
      declarations = result.fetch("scopes").first.fetch("declarations").to_h { |row| [row.fetch("id"), row] }
      attributes = lens.fetch("bindings").select { |binding| %w[name code].include?(declarations.fetch(binding.fetch("declaration_id")).fetch("name")) }
      assert_equal 2, attributes.size
      assert_equal 2, attributes.map { |binding| binding.fetch("site_key") }.uniq.size
      scale = lens.fetch("members").find { |member| member.fetch("name") == "scale" }
      assert_equal "contract", scale.fetch("basis")
      assert_nil scale.fetch("overloads").first.fetch("rbs")
      assert_equal({"state" => "unavailable", "reason" => "contested"}, scale.fetch("overloads").first.fetch("return"))
      fetch = lens.fetch("members").find { |member| member.fetch("name") == "fetch" }
      assert_equal "contested", fetch.fetch("basis")
      assert_empty fetch.fetch("overloads")
      refute lens.fetch("members").any? { |member| member.fetch("name") == "secret" }
      assert lens.fetch("bindings").all? { |binding| binding.fetch("status") == "matched" }
    end
  end

  def test_explains_an_exact_producer_omission_without_attaching_other_facts
    with_project do |root, export|
      data = fixture_document
      file = data.fetch("files").find { |item| item.fetch("path") == "lib/shop.rb" }
      site = file.fetch("sites").find { |item| item.fetch("kind") == "constant" }
      file.fetch("sites").delete(site)
      file["complete"] = false
      file["omissions"] = [{"kind" => "constant", "name" => site.fetch("name"), "reason" => "unsupported", "span" => site.fetch("span")}]
      lens = adapter(root, data).enrich(export, base: root).fetch("lens")
      binding = lens.fetch("bindings").find { |item| item["reason"] == "unsupported_declaration" }
      assert_equal({"kind" => "constant", "reason" => "unsupported"}, binding.fetch("omission"))
      assert_nil binding.fetch("site_key")
      assert_empty binding.fetch("member_keys")
    end
  end

  def test_keeps_documentation_scopes_independent_and_rejects_stale_offsets_and_digests
    with_project do |root, export|
      other = JSON.parse(JSON.generate(export.fetch("scopes").first))
      other["name"] = "other"
      other["declarations"].each { |row| row["id"] = "other:#{row.fetch("anchor")}" }
      export.fetch("scopes") << other
      result = adapter(root).enrich(export, base: root)
      assert_equal %w[app other], result.fetch("lens").fetch("bindings").map { |binding| binding.fetch("scope") }.uniq
      bad = fixture_document
      bad.fetch("files").first["digest"] = "xxh3-64:0000000000000000"
      assert_raises(Zard::Rigor::Error) { adapter(root, bad).enrich(export, base: root) }
      bad = fixture_document
      bad.fetch("files").first.fetch("sites").first.fetch("span")["start_line"] += 1
      assert_raises(Zard::Rigor::Error) { adapter(root, bad).enrich(export, base: root) }
      bad = fixture_document
      file = bad.fetch("files").first
      span = file.fetch("sites").first.fetch("span").dup
      span["end_offset"] += 1
      file["complete"] = false
      file["omissions"] = [{"kind" => "method", "name" => "amount", "reason" => "unsupported", "span" => span}]
      assert_raises(Zard::Rigor::Error) { adapter(root, bad).enrich(export, base: root) }
      assert_raises(Zard::Rigor::Error) do
        adapter(root) { File.write(File.join(root, "lib/shop.rb"), "# changed\n") }.enrich(export, base: root)
      end
    end
  end

  def test_rejects_incompatible_transport_and_dangling_fact_references
    with_project do |root, export|
      mutations = [
        ->(data) { data["revision"] = 2 },
        ->(data) { data.fetch("producer")["version"] = "0.4.3" },
        ->(data) { data.fetch("producer")["version"] = "0.4.4" },
        ->(data) { data.fetch("files").pop },
        ->(data) { data.fetch("members").first["sites"] = ["missing"] },
        ->(data) { data.fetch("members").find { |member| member["basis"] == "contested" }["overloads"] = [{}] }
      ]
      mutations.each do |mutation|
        data = fixture_document
        mutation.call(data)
        assert_raises(Zard::Rigor::Error) { adapter(root, data).enrich(export, base: root) }
      end
      runner = ->(*, **) { ["{truncated", "", Struct.new(:exitstatus).new(0)] }
      assert_raises(Zard::Rigor::Error) { Zard::Rigor::Lens.new(root: root, runner: runner).enrich(export, base: root) }
      runner = ->(*, **) { ["", "bad flags", Struct.new(:exitstatus).new(64)] }
      assert_raises(Zard::Rigor::Error) { Zard::Rigor::Lens.new(root: root, runner: runner).enrich(export, base: root) }
    end
  end

  def test_preserves_partial_results_without_attaching_facts_to_failed_targets
    with_project do |root, export|
      data = fixture_document
      failed = data.fetch("files").find { |file| file["path"] == "lib/util.rb" }
      keys = failed.fetch("sites").map { |site| site.fetch("key") }
      failed.merge!("status" => "outside_project", "reason" => "excluded", "sites" => nil, "digest" => nil, "complete" => nil, "omissions" => nil, "inputs" => nil)
      data.fetch("members").reject! { |member| (member.fetch("sites") & keys).any? }
      result = adapter(root, data).enrich(export, base: root)
      assert result.fetch("lens").fetch("bindings").any? { |binding| binding["reason"] == "outside_project" }
      assert_equal "excluded", result.fetch("lens").fetch("bindings").find { |binding| binding["reason"] == "outside_project" }.fetch("detail")
      assert result.fetch("lens").fetch("bindings").any? { |binding| binding["status"] == "matched" }
    end
  end

  def test_released_cli_when_available
    command = ENV["ZARD_RIGOR_COMMAND"]
    skip "Set ZARD_RIGOR_COMMAND for released Rigor integration" unless command

    with_project do |root, export|
      lens = Zard::Rigor::Lens.new(root: root, command: command).enrich(export, base: root).fetch("lens")
      assert_equal "0.4.5", lens.fetch("producer").fetch("version")
      expected = fixture_document
      assert_equal expected.fetch("files").map { |file| file.fetch("digest") }, lens.fetch("files").map { |file| file.fetch("digest") }
      expected_members = expected.fetch("members").select do |member|
        lens.fetch("members").any? { |actual| actual.values_at("owner", "scope", "name") == member.values_at("owner", "scope", "name") }
      end
      identity = ->(member) { member.values_at("owner", "scope", "name") }
      actual_members = lens.fetch("members").map { |member| member.except("key") }
      assert_equal expected_members.sort_by(&identity), actual_members.sort_by(&identity)
      assert_equal 20, lens.fetch("bindings").size
      rows = export.fetch("scopes").first.fetch("declarations")
      %w[LIMIT title helper].each do |name|
        row = rows.find { |item| item.fetch("name") == name }
        binding = lens.fetch("bindings").find { |item| item.fetch("declaration_id") == row.fetch("id") }
        assert_equal "matched", binding.fetch("status"), name
        if name == "helper"
          assert_equal ["singleton"], binding.fetch("member_keys").map { |key| JSON.parse(key)[1] }
        end
      end
      refute lens.fetch("members").any? { |member| member.values_at("owner", "scope") == ["Util", "instance"] }
    end
  end

  def test_cli_rejects_lens_misconfiguration_and_emits_no_partial_export
    with_project do |root, export|
      config = File.join(root, "zard-doc.yml")
      [
        ["--lens-root", root],
        ["--format", "json", "--lens-config", ".rigor.yml"],
        ["--format", "json", "--lens-root", root, "--lens-workers", "-1"],
        ["--format", "json", "--lens-root", root, "--rigor-command", File.join(root, "missing-rigor")]
      ].each do |options|
        output = StringIO.new
        errors = StringIO.new
        status = Zard::Doc::CLI.run(["build", "--config", config, *options], stdout: output, stderr: errors)
        refute_equal 0, status
        assert_empty output.string
        refute_empty errors.string
      end
      document = fixture_document
      document["files"].each do |file|
        file.merge!("status" => "failed", "reason" => "producer failed", "sites" => nil)
      end
      document["members"] = []
      error = assert_raises(Zard::Rigor::Error) { adapter(root, document, status: 1).enrich(export, base: root) }
      assert_match(/no successful targets/, error.message)
    end
  end
end
