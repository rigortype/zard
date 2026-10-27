# frozen_string_literal: true

require "test_helper"
require "json"
require "zard/rigor"

class RigorTypeReferencesTest < Minitest::Test
  KEY = JSON.generate(["App::Box", "instance", "call"])

  def test_contract_names_keep_spelling_and_byte_ranges_while_type_variables_and_literals_are_not_references
    text = %([T] (::Box[T] input, "ä" mark, :sym tag, 1 count, bool flag) { (T) -> ::App::Foo } -> (::App::Foo | singleton(::Box) | _Local | self)?)
    result = attach(text, "::Box" => [candidate("app", "class")], "::App::Foo" => [candidate("app", "module", "foo")])
    references = result.fetch("type_references")
    assert_equal ["::Box", "::App::Foo", "::App::Foo", "::Box"], references.map { |reference| reference.fetch("name") }
    references.each do |reference|
      assert_equal reference.fetch("name"), text.byteslice(reference.fetch("start_offset")...reference.fetch("end_offset"))
      assert_equal "resolved", reference.fetch("status")
      assert_equal [KEY, 0], reference.values_at("member_key", "overload")
    end
    assert_operator references.first.fetch("start_offset"), :<, references[1].fetch("start_offset")
    assert_empty result.fetch("type_reference_diagnostics")
  end

  def test_generic_bounds_are_traversed
    result = attach("[T < ::Base] (T) -> T", "::Base" => [candidate("app", "class", "base")])
    assert_equal [["::Base", "resolved"]], result.fetch("type_references").map { |reference| reference.values_at("name", "status") }
  end

  def test_inferred_returns_spell_full_paths_without_a_leading_separator
    calls = []
    resolve = lambda do |scope, name|
      calls << [scope, name]
      [candidate("app", "class")]
    end
    overload = {"rbs" => "(::App::Foo) -> [App::Foo, Inf]", "return" => {"provenance" => "inferred"}}
    result = attach_overloads([overload], resolve)
    assert_equal ["::App::Foo", "App::Foo", "Inf"], result.fetch("type_references").map { |reference| reference.fetch("name") }
    assert_equal [["app", "::App::Foo"], ["app", "::Inf"]], calls
  end

  def test_relative_names_in_contract_text_are_never_resolved
    calls = []
    resolve = lambda do |_scope, name|
      calls << name
      []
    end
    result = attach_overloads([{"rbs" => "() -> T"}, {"rbs" => "(Odd::Name) -> App::Foo", "return" => {"provenance" => "inferred"}}], resolve)
    assert_equal ["App::Foo"], result.fetch("type_references").map { |reference| reference.fetch("name") }
    assert_equal ["::App::Foo"], calls
    assert_equal ["app:App::Box#call overload 1: unqualified type name Odd::Name in a contract signature; text retained literally"],
      result.fetch("type_reference_diagnostics")
  end

  def test_missing_names_stay_literal_without_noise
    reference = attach("() -> ::String", {}).fetch("type_references").first
    assert_equal ["unresolved", "missing", [], []], reference.values_at("status", "reason", "targets", "candidates")
  end

  def test_ambiguous_candidates_keep_every_location_and_only_documented_targets
    result = attach("() -> ::Twin", "::Twin" => [candidate("left", "class"), candidate("right", "class", "twin", published: false)])
    reference = result.fetch("type_references").first
    assert_equal "ambiguous", reference.fetch("status")
    assert_equal %w[left right], reference.fetch("candidates").map { |item| item.fetch("scope") }
    assert_equal ["left"], reference.fetch("targets").map { |item| item.fetch("scope") }
    assert_equal ["app:App::Box#call overload 0: ambiguous type reference ::Twin; candidates: left:lib/types.rb:1, right:lib/types.rb:1"],
      result.fetch("type_reference_diagnostics")
  end

  def test_unlinkable_single_candidates_explain_why
    excluded = attach("() -> ::Hidden", "::Hidden" => [candidate("app", "class", "hidden", published: false)])
    assert_equal "unpublished", excluded.fetch("type_references").first.fetch("reason")
    assert_match(/its declaration at app:lib\/types.rb:1 is excluded from publication/, excluded.fetch("type_reference_diagnostics").first)
    constant = attach("() -> ::LIMIT", "::LIMIT" => [candidate("app", "constant", "limit")])
    assert_equal ["unresolved", "not_class_or_module"], constant.fetch("type_references").first.values_at("status", "reason")
    assert_match(/app:lib\/types.rb:1 is a constant declaration, not a class or module/, constant.fetch("type_reference_diagnostics").first)
    built = attach("() -> ::Point", "::Point" => [candidate("app", "constant", "point", container_builder: true)])
    assert_equal ["resolved"], built.fetch("type_references").map { |reference| reference.fetch("status") }
  end

  def test_unparseable_text_is_retained_with_a_diagnostic
    result = attach("() -> non-empty-string", {})
    assert_empty result.fetch("type_references")
    assert_equal ["app:App::Box#call overload 0: signature is not supported RBS syntax; text retained literally"], result.fetch("type_reference_diagnostics")
    nested = attach("() -> void\n  def other: () -> void", {})
    assert_match(/unsupported signature structure/, nested.fetch("type_reference_diagnostics").first)
  end

  private

  def attach(text, table)
    attach_overloads([{"rbs" => text}], ->(_scope, name) { table.fetch(name, []) })
  end

  def attach_overloads(overloads, resolve)
    members = [{"key" => KEY, "owner" => "App::Box", "scope" => "instance", "name" => "call", "overloads" => overloads}]
    rows = %w[app left right].map do |scope|
      {"name" => scope, "declarations" => %w[box foo base twin hidden limit point].map do |suffix|
        {"id" => "#{scope}:#{suffix}", "page" => "#{scope}/#{suffix}.md", "anchor" => "zard-#{suffix.unpack1("H*")}"}
      end}
    end
    resolver = Zard::Rigor.const_get(:TypeReferences).new({"scopes" => rows}, members, resolve)
    resolver.attach({"scope" => "app", "declaration_id" => "app:call", "member_keys" => [KEY]})
  end

  def candidate(scope, kind, suffix = "box", published: true, container_builder: false)
    {"scope" => scope, "declaration_id" => (published ? "#{scope}:#{suffix}" : nil), "kind" => kind,
     "container_builder" => container_builder, "span" => {"path" => "lib/types.rb", "start_line" => 1, "end_line" => 3}}
  end
end
