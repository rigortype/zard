# frozen_string_literal: true

require "test_helper"
require "zard/rigor"

class RigorTypeReferencesTest < Minitest::Test
  KEY = JSON.generate(["Box", "instance", "call"])

  def test_rbs_traversal_preserves_ranges_and_excludes_type_variables
    text = "[T] (Box[T] input) { (T) -> Foo } -> ::Foo"
    result = resolve(text, [scope("app", [row("Box"), row("Foo")])])
    references = result.fetch("type_references")
    assert_equal ["Box", "Foo", "::Foo"], references.map { |reference| reference.fetch("name") }
    assert references.all? { |reference| reference.fetch("status") == "resolved" }
    references.each do |reference|
      assert_equal reference.fetch("name"), text.byteslice(reference.fetch("start_offset")...reference.fetch("end_offset"))
    end
    assert_empty result.fetch("type_reference_diagnostics")
  end

  def test_local_scope_wins_over_direct_dependencies
    result = resolve("() -> Foo", [scope("app", [row("Foo")], ["dep"]), scope("dep", [row("Foo", "dep")])])
    assert_equal ["app"], result.fetch("type_references").first.fetch("targets").map { |target| target.fetch("scope") }
  end

  def test_local_ambiguity_does_not_fall_through_to_dependency
    result = resolve("() -> Foo", [scope("app", [row("Foo"), row("Foo", "app", "second")], ["dep"]), scope("dep", [row("Foo", "dep")])])
    reference = result.fetch("type_references").first
    assert_equal "ambiguous", reference.fetch("status")
    assert_equal ["app", "app"], reference.fetch("targets").map { |target| target.fetch("scope") }
    assert_match(/app:Foo at lib\/types.rb:1/, result.fetch("type_reference_diagnostics").first)
  end

  def test_lookup_does_not_leak_through_transitive_dependencies
    result = resolve("() -> Foo", [scope("app", [], ["dep"]), scope("dep", [], ["far"]), scope("far", [row("Foo", "far")])])
    reference = result.fetch("type_references").first
    assert_equal "unresolved", reference.fetch("status")
    assert_empty reference.fetch("targets")
    assert_match(/no documented declaration/, result.fetch("type_reference_diagnostics").first)
  end

  def test_competing_direct_dependencies_remain_ambiguous
    result = resolve("() -> Foo", [scope("app", [], %w[left right]), scope("left", [row("Foo", "left")]), scope("right", [row("Foo", "right")])])
    reference = result.fetch("type_references").first
    assert_equal "ambiguous", reference.fetch("status")
    assert_equal %w[left right], reference.fetch("targets").map { |target| target.fetch("scope") }
  end

  private

  def resolve(text, scopes)
    members = [{"key" => KEY, "owner" => "Box", "scope" => "instance", "name" => "call", "overloads" => [{"rbs" => text}]}]
    resolver = Zard::Rigor.const_get(:TypeReferences).new({"scopes" => scopes}, members)
    resolver.attach({"scope" => "app", "declaration_id" => "app:call", "member_keys" => [KEY]})
  end

  def scope(name, declarations, references = [])
    {"name" => name, "declarations" => declarations, "references" => references}
  end

  def row(name, scope = "app", suffix = name)
    {"id" => "#{scope}:#{suffix}", "kind" => "class", "display_name" => name,
     "page" => "#{scope}/#{name}.md", "anchor" => "zard-#{suffix.unpack1("H*")}",
     "span" => {"path" => "lib/types.rb", "start_line" => 1, "end_line" => 3}}
  end
end
