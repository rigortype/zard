# frozen_string_literal: true

require "test_helper"
require "zard/doc/cli"
require "zard/rigor"
require "tmpdir"
require "fileutils"
require "stringio"

class RigorTypeReferenceLinksTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/rigor_lens/type_references", __dir__)
  ASTRO = File.expand_path("../zard-doc-astro/test/fixtures", __dir__)

  def test_resolves_local_then_direct_dependencies_without_widening_visibility
    with_project do |root|
      data = build(root)
      assert_equal "resolved", status(data, "App::Service#call", "::App::Common")
      assert_equal ["app"], target_scopes(data, "App::Service#call", "::App::Common")
      assert_equal ["shared"], target_scopes(data, "App::Service#across", "::Shared::Thing")
      assert_equal ["unresolved", "missing"], reference(data, "App::Service#across", "::Far").values_at("status", "reason")
      assert_equal ["far"], target_scopes(data, "Shared::Thing#link", "::Far")
      assert_equal ["app"], target_scopes(data, "Shared::Thing#link", "::App::Foo")
      assert_equal ["unresolved", "missing"], reference(data, "App::Service#elsewhere", "::Lonely").values_at("status", "reason")
      twin = reference(data, "App::Service#across", "::Twin")
      assert_equal "ambiguous", twin.fetch("status")
      assert_equal %w[left right], twin.fetch("candidates").map { |item| item.fetch("scope") }
      warnings = data.fetch("lens").fetch("warnings")
      assert_includes warnings, "app:App::Service#across overload 0: ambiguous type reference ::Twin; candidates: left:lib/left/twin.rb:2, right:lib/right/twin.rb:2"
      assert_includes warnings, "app:App::Service#elsewhere overload 0: type reference ::App::Hidden left literal; its declaration at app:lib/app/types.rb:13 is excluded from publication"
      assert_equal 2, warnings.count { |warning| warning.include?("type reference") }
    end
  end

  def test_type_variables_builtins_inferred_returns_and_overloads
    with_project do |root|
      data = build(root)
      assert_empty references(data, "App::Box#get")
      assert_equal %w[::Hash ::Symbol ::App::Foo], references(data, "App::Box#map").map { |item| item.fetch("name") }
      assert_equal ["::Array", "::Hash", "::Symbol", "::App::Foo", "::App::Foo", "::App::Common", "::App::Foo"],
        references(data, "App::Service#call").map { |item| item.fetch("name") }
      assert_equal ["resolved"], references(data, "App::Service#make").map { |item| item.fetch("status") }
      assert_equal "App::Foo", references(data, "App::Service#make").first.fetch("name")
      assert_equal [[0, "::Integer"], [0, "::App::Foo"], [1, "::String"], [1, "::App::Common"]],
        references(data, "App::Service#convert").map { |item| item.values_at("overload", "name") }
      assert_equal "resolved", status(data, "App::Service#elsewhere", "::App::Point")
      assert_equal "unresolved", status(data, "App::Service#across", "::_ToS")
    end
  end

  def test_destinations_exist_in_both_layouts_and_reopened_types_use_their_first_definition
    with_project do |root|
      %w[namespace file].each do |layout|
        data = build(root, layout: layout)
        rows = data.fetch("scopes").flat_map { |scope| scope.fetch("declarations").map { |row| [row.fetch("id"), row] } }.to_h
        targets = data.fetch("lens").fetch("bindings").flat_map { |binding| binding.fetch("type_references") }.flat_map { |item| item.fetch("targets") }
        refute_empty targets
        targets.each do |target|
          row = rows.fetch(target.fetch("declaration_id"))
          assert_equal row.values_at("page", "anchor"), target.values_at("path", "anchor")
          assert_equal row.fetch("span").slice("path", "start_line", "end_line"), target.fetch("span")
        end
        foo = reference(data, "App::Service#call", "::App::Foo").fetch("targets").first
        assert_equal "lib/app/reopened.rb", foo.fetch("span").fetch("path")
        assert_equal((layout == "file") ? "app/reopened.md" : "app/App/Foo.md", foo.fetch("path"))
      end
    end
  end

  def test_enrichment_without_constant_resolution_leaves_signatures_literal
    with_project do |root|
      output = StringIO.new
      assert_equal 0, Zard::Doc::CLI.run(["build", "--config", File.join(root, "zard-doc.yml"), "--format", "json"], stdout: output, stderr: StringIO.new)
      lens = lens(root).enrich(JSON.parse(output.string), base: root).fetch("lens")
      assert lens.fetch("bindings").none? { |binding| binding.key?("type_references") }
    end
  end

  def test_released_cli_reproduces_type_reference_exports_when_available
    command = ENV["ZARD_RIGOR_COMMAND"]
    skip "Set ZARD_RIGOR_COMMAND for released Rigor integration" unless command

    with_project do |root|
      {"namespace" => "type-references-export.json", "file" => "type-references-file-export.json"}.each do |layout, name|
        output = StringIO.new
        errors = StringIO.new
        arguments = ["build", "--config", File.join(root, "zard-doc.yml"), "--format", "json", "--layout", layout,
          "--lens-root", root, "--rigor-command", command, "--lens-workers", "0"]
        assert_equal 0, Zard::Doc::CLI.run(arguments, stdout: output, stderr: errors), errors.string
        actual = JSON.parse(output.string)
        assert_equal "0.4.5", actual.fetch("lens").fetch("producer").fetch("version")
        assert_equal build(root, layout: layout), actual
        assert_equal JSON.parse(File.read(File.join(ASTRO, name))), actual
      end
    end
  end

  private

  def references(data, member)
    owner, name = member.split("#")
    key = JSON.generate([owner, "instance", name])
    bindings = data.fetch("lens").fetch("bindings").select { |binding| binding.fetch("member_keys").include?(key) }
    assert_equal 1, bindings.size, member
    bindings.first.fetch("type_references")
  end

  def reference(data, member, name)
    matches = references(data, member).select { |item| item.fetch("name") == name }
    refute_empty matches, "#{member} #{name}"
    matches.first
  end

  def status(data, member, name)
    reference(data, member, name).fetch("status")
  end

  def target_scopes(data, member, name)
    item = reference(data, member, name)
    assert_equal "resolved", item.fetch("status")
    item.fetch("targets").map { |target| target.fetch("scope") }
  end

  def build(root, layout: "namespace")
    output = StringIO.new
    adapter = lens(root)
    enricher = ->(data, base:, resolve_constant:) { adapter.enrich(data, base: base, resolve_constant: resolve_constant) }
    builder = Zard::Doc.const_get(:Build).new(File.join(root, "zard-doc.yml"), layout: layout, format: "json", stdout: output, enricher: enricher)
    assert_equal 0, builder.run, builder.diagnostics.join("\n")
    JSON.parse(output.string)
  end

  def lens(root)
    runner = lambda do |*arguments, **options|
      assert_equal File.realpath(root), options.fetch(:chdir)
      assert_equal ["rigor", "lens", "--format=json", "--workers", "4"], arguments.first(5)
      assert_equal Dir.chdir(root) { Dir["lib/**/*.rb"].sort.map { |path| "./#{path}" } }, arguments.drop(5)
      [File.read(File.join(FIXTURE, "expected.json")), "", Struct.new(:exitstatus).new(0)]
    end
    Zard::Rigor::Lens.new(root: root, runner: runner)
  end

  def with_project
    Dir.mktmpdir("zard-type-references-") do |root|
      %w[lib sig .rigor.yml zard-doc.yml].each { |path| FileUtils.cp_r(File.join(FIXTURE, path), root) }
      yield root
    end
  end
end
