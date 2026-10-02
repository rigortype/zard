# frozen_string_literal: true

require "test_helper"

class ParserTest < Minitest::Test
  def test_parses_the_first_vertical_slice
    path = File.expand_path("fixtures/read_name.rb", __dir__)
    document = Zard.parse(File.read(path), path: path)
    declaration = document.declarations.fetch(0)

    assert_empty document.diagnostics
    assert_equal :instance_method, declaration.kind
    assert_equal "read_name", declaration.name
    assert_nil declaration.namespace
    assert_equal ["path"], declaration.parameters
    assert_equal %i[extrbs rbs rbs], declaration.contracts.map(&:channel)
    assert_equal %i[param return], declaration.documentation.map(&:name)
    assert_equal "Path to the name file.", declaration.documentation.fetch(0).description
    assert_equal "The stored name.", declaration.documentation.fetch(1).description
    assert_equal 1, declaration.comment_span.start_line
    assert_equal 6, declaration.span.start_line
  end

  def test_preserves_yard_like_tags_as_raw_text
    source = "# @param value [String] Input text.\ndef call(value) = value\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal [:raw], document.declarations.fetch(0).documentation.map(&:name)
    assert_equal ["documentation.yard-like"], document.diagnostics.map(&:code)
  end

  def test_accepts_redundant_return_marker_with_a_warning
    source = "# @return — Value.\ndef call = 1\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal "Value.", document.declarations.fetch(0).documentation.fetch(0).description
    assert_equal ["documentation.redundant-marker"], document.diagnostics.map(&:code)
  end

  def test_reports_noncanonical_extrbs_layout
    source = "# @rbs return: String\n#  @extrbs return: non-empty-string\ndef call = \"value\"\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal %w[extrbs.noncanonical-spacing extrbs.not-first], document.diagnostics.map(&:code)
  end

  def test_reports_extrbs_without_the_required_space
    document = Zard.parse("\#@extrbs return: non-empty-string\ndef call = \"value\"\n", path: "example.rb")

    assert_equal ["extrbs.noncanonical-spacing"], document.diagnostics.map(&:code)
    assert_equal [:extrbs], document.declarations.fetch(0).contracts.map(&:channel)
  end

  def test_keeps_consecutive_extrbs_annotations_first
    source = "# @extrbs value: non-empty-string\n# @extrbs return: non-empty-string\n# @rbs return: String\ndef call(value) = value\n"
    document = Zard.parse(source, path: "example.rb")

    assert_empty document.diagnostics
    assert_equal %i[extrbs extrbs rbs], document.declarations.fetch(0).contracts.map(&:channel)
  end

  def test_collects_namespace_singleton_kind_and_parameter_shapes
    source = "module Demo\n  class Reader\n    # @return Value.\n    def self.read(path, mode: :text, **options, &block) = path\n  end\nend\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal "Demo::Reader", declaration.namespace
    assert_equal :singleton_method, declaration.kind
    assert_equal ["path", "mode:", "**options", "&block"], declaration.parameters
  end

  def test_resets_the_namespace_for_an_absolute_constant_path
    source = "module Outer\n  class ::Reader\n    def read = nil\n  end\nend\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal "Reader", declaration.namespace
  end

  def test_collects_forwarding_parameters
    declaration = Zard.parse("def call(...) = target(...)\n", path: "example.rb").declarations.fetch(0)

    assert_equal ["..."], declaration.parameters
  end

  def test_does_not_treat_longer_tag_names_as_known_tags
    source = "# @parameter value — Text.\ndef call(value) = value\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal [:raw], document.declarations.fetch(0).documentation.map(&:name)
    assert_empty document.diagnostics
  end

  def test_parses_nested_documentation_claims_without_rendering_them
    source = "# @param values [Array[String]] — Values.\n# @return [Array[String]] — Copies.\ndef copy(values) = values.dup\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal ["Array[String]", "Array[String]"], declaration.documentation.map(&:claim)
    assert_equal ["Values.", "Copies."], declaration.documentation.map(&:description)
  end

  def test_parses_yield_documentation_with_the_param_and_return_rules
    source = "# @yieldparam value [String] — Each value.\n# @yieldreturn [Integer] — The consumed length.\ndef each_value = yield(\"value\")\n"
    document = Zard.parse(source, path: "example.rb")
    documentation = document.declarations.fetch(0).documentation

    assert_empty document.diagnostics
    assert_equal %i[yieldparam yieldreturn], documentation.map(&:name)
    assert_equal ["String", "Integer"], documentation.map(&:claim)
    assert_equal ["value", nil], documentation.map(&:subject)
  end

  def test_preserves_yard_like_yieldparam_as_raw_text
    source = "# @yieldparam value [String] Each value.\ndef each_value = yield(\"value\")\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal [:raw], document.declarations.fetch(0).documentation.map(&:name)
    assert_equal ["documentation.yard-like"], document.diagnostics.map(&:code)
  end
end
