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

    assert_equal ["extrbs.noncanonical-spacing"], document.diagnostics.map(&:code)
    assert_equal [:raw], document.declarations.fetch(0).documentation.map(&:name)
  end

  def test_reports_extrbs_without_the_required_space
    document = Zard.parse("\#@extrbs return: non-empty-string\ndef call = \"value\"\n", path: "example.rb")

    assert_equal ["extrbs.noncanonical-spacing"], document.diagnostics.map(&:code)
    assert_empty document.declarations.fetch(0).contracts
  end

  def test_keeps_consecutive_extrbs_annotations_first
    source = "# @extrbs value: non-empty-string\n# @extrbs return: non-empty-string\n# @rbs return: String\ndef call(value) = value\n"
    document = Zard.parse(source, path: "example.rb")

    assert_empty document.diagnostics
    assert_equal %i[extrbs extrbs rbs], document.declarations.fetch(0).contracts.map(&:channel)
  end

  def test_collects_namespace_singleton_kind_and_parameter_shapes
    source = "module Demo\n  class Reader\n    # @return Value.\n    def self.read(path, mode: :text, **options, &block) = path\n  end\nend\n"
    declarations = Zard.parse(source, path: "example.rb").declarations
    declaration = declarations.find { |item| item.kind == :singleton_method }

    assert_equal "Demo::Reader", declaration.namespace
    assert_equal :singleton_method, declaration.kind
    assert_equal ["path", "mode:", "**options", "&block"], declaration.parameters
  end

  def test_collects_documented_modules_and_classes_before_their_members
    source = "# Public API.\nmodule Demo\n  # Reads stored values.\n  class Reader\n    # @return Stored value.\n    def read = nil\n  end\nend\n"
    document = Zard.parse(source, path: "example.rb")
    mod, klass, method = document.declarations

    assert_empty document.diagnostics
    assert_equal [:module, :class, :instance_method], document.declarations.map(&:kind)
    assert_equal ["Demo", "Reader", "read"], document.declarations.map(&:name)
    assert_equal [nil, "Demo", "Demo::Reader"], document.declarations.map(&:namespace)
    assert_equal [[], [], []], document.declarations.map(&:parameters)
    assert_equal ["Public API.", "Reads stored values.", "Stored value."], [mod, klass, method].map { |item| item.documentation.fetch(0).description }
  end

  def test_collects_qualified_and_absolute_class_declarations
    source = "class Demo::Reader\nend\nmodule Outer\n  class ::Root\n    def read = nil\n  end\nend\n"
    declarations = Zard.parse(source, path: "example.rb").declarations

    assert_equal [
      [:class, "Reader", "Demo"],
      [:module, "Outer", nil],
      [:class, "Root", nil],
      [:instance_method, "read", "Root"]
    ], declarations.map { |declaration| [declaration.kind, declaration.name, declaration.namespace] }
  end

  def test_collects_simple_qualified_and_absolute_constant_declarations
    source = "module Demo\n  # Default limit.\n  LIMIT = 3\nend\nDemo::VERSION = \"1.0\"\nmodule Outer\n  ::ROOT = true\nend\n"
    declarations = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind == :constant }

    assert_equal [
      ["LIMIT", "Demo"],
      ["VERSION", "Demo"],
      ["ROOT", nil]
    ], declarations.map { |declaration| [declaration.name, declaration.namespace] }
    assert_equal "Default limit.", declarations.fetch(0).documentation.fetch(0).description
    assert_equal [], declarations.fetch(0).parameters
  end

  def test_does_not_collect_constant_reassignments_as_declarations
    source = "VALUE ||= 1\nVALUE &&= 2\nVALUE += 3\n"
    declarations = Zard.parse(source, path: "example.rb").declarations

    assert_empty declarations
  end

  def test_collects_instance_attributes_with_shared_documentation
    source = "class Reader\n  # Names exposed by the reader.\n  attr_reader :name, \"alias_name\"\n  attr_writer :token\n  attr_accessor(:enabled)\nend\n"
    attributes = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind.to_s.include?("attribute") }

    assert_equal %i[instance_attribute_reader instance_attribute_reader instance_attribute_writer instance_attribute_accessor], attributes.map(&:kind)
    assert_equal ["name", "alias_name", "token", "enabled"], attributes.map(&:name)
    assert_equal ["Reader"] * 4, attributes.map(&:namespace)
    assert_equal "Names exposed by the reader.", attributes.fetch(0).documentation.fetch(0).description
    assert_equal attributes.fetch(0).comment_span.start_offset, attributes.fetch(1).comment_span.start_offset
    assert_equal attributes.fetch(0).comment_span.end_offset, attributes.fetch(1).comment_span.end_offset
  end

  def test_reports_a_shared_attribute_comment_diagnostic_once
    source = "class Reader\n  #  @note Shared description.\n  attr_reader :name, :age\nend\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal ["documentation.noncanonical-spacing"], document.diagnostics.map(&:code)
  end

  def test_collects_singleton_attributes_inside_a_singleton_class
    source = "class Reader\n  class << self\n    # Current format version.\n    attr_accessor :version\n  end\nend\n"
    attribute = Zard.parse(source, path: "example.rb").declarations
      .find { |declaration| declaration.kind == :singleton_attribute_accessor }

    assert_equal "version", attribute.name
    assert_equal "Reader", attribute.namespace
  end

  def test_ignores_dynamic_received_and_top_level_attribute_calls
    source = "attr_reader :top_level\nclass Reader\n  attr_reader(*NAMES)\n  helper.attr_reader :received\nend\n"
    attributes = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind.to_s.include?("attribute") }

    assert_empty attributes
  end

  def test_tracks_lexical_and_inline_method_visibility
    source = "class Reader\n  def visible = nil\n  private\n  def hidden = nil\n  protected def inherited = nil\n  public def shown = nil\n  def self.version = nil\nend\n"
    methods = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind.to_s.end_with?("method") }

    assert_equal [
      ["visible", :public],
      ["hidden", :private],
      ["inherited", :protected],
      ["shown", :public],
      ["version", :public]
    ], methods.map { |declaration| [declaration.name, declaration.visibility] }
  end

  def test_resets_visibility_for_nested_and_singleton_classes
    source = "class Outer\n  private\n  class Inner\n    def visible = nil\n  end\n  def hidden = nil\n  class << self\n    private\n    def internal = nil\n    public\n    def version = nil\n  end\nend\n"
    methods = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind.to_s.end_with?("method") }

    assert_equal [
      ["visible", :public],
      ["hidden", :private],
      ["internal", :private],
      ["version", :public]
    ], methods.map { |declaration| [declaration.name, declaration.visibility] }
  end

  def test_tracks_lexical_and_inline_attribute_visibility
    source = "class Reader\n  private attr_reader :token\n  protected\n  attr_writer :name\n  public\n  attr_accessor :enabled\nend\n"
    attributes = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind.to_s.include?("attribute") }

    assert_equal [
      ["token", :private],
      ["name", :protected],
      ["enabled", :public]
    ], attributes.map { |declaration| [declaration.name, declaration.visibility] }
  end

  def test_resets_the_namespace_for_an_absolute_constant_path
    source = "module Outer\n  class ::Reader\n    def read = nil\n  end\nend\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.find { |item| item.kind == :instance_method }

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

  def test_parses_options_and_raised_exceptions
    source = "# @option options :format — Output format.\n# @option options :limit [Integer] — Maximum count.\n# @raise IOError — If the input cannot be read.\ndef read(**options) = nil\n"
    document = Zard.parse(source, path: "example.rb")
    documentation = document.declarations.fetch(0).documentation

    assert_empty document.diagnostics
    assert_equal %i[option option raise], documentation.map(&:name)
    assert_equal ["options", "options", nil], documentation.map(&:owner)
    assert_equal [":format", ":limit", "IOError"], documentation.map(&:subject)
    assert_equal [nil, "Integer", nil], documentation.map(&:claim)
  end

  def test_preserves_yard_like_option_as_raw_text
    source = "# @option options [Symbol] :format Output format.\ndef read(**options) = nil\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal [:raw], document.declarations.fetch(0).documentation.map(&:name)
    assert_equal ["documentation.yard-like"], document.diagnostics.map(&:code)
  end

  def test_parses_description_only_tags_without_type_claims
    source = "# @note Thread-safe after initialization.\n# @see https://example.test/reference\n# @deprecated Use #fetch instead.\n# @example reader.read\ndef read = nil\n"
    document = Zard.parse(source, path: "example.rb")
    documentation = document.declarations.fetch(0).documentation

    assert_empty document.diagnostics
    assert_equal %i[note see deprecated example], documentation.map(&:name)
    assert documentation.all? { |tag| tag.owner.nil? && tag.subject.nil? && tag.claim.nil? }
    assert_equal "Thread-safe after initialization.", documentation.fetch(0).description
    assert_equal "reader.read", documentation.fetch(3).description
  end

  def test_rejects_documentation_in_a_non_utf8_source
    source = "# encoding: Windows-31J\n# @return 名前\ndef call = nil\n".encode("Windows-31J")
    document = Zard.parse(source, path: "example.rb")

    assert_equal [:raw], document.declarations.fetch(0).documentation.map(&:name)
    assert_equal ["documentation.non-utf8"], document.diagnostics.map(&:code)
    assert_equal :error, document.diagnostics.fetch(0).severity
  end

  def test_accepts_contracts_in_a_non_utf8_source
    source = "# encoding: Windows-31J\n# @rbs return: String\ndef call = nil\n".encode("Windows-31J")
    document = Zard.parse(source, path: "example.rb")

    assert_empty document.diagnostics
    assert_equal [:rbs], document.declarations.fetch(0).contracts.map(&:channel)
  end

  def test_separates_contract_notes_from_type_payloads
    source = "# @extrbs return: non-empty-string -- Guaranteed by validation.\n# @rbs return: String -- Public return type.\n# @return The stored value.\ndef call = \"value\"\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal ["return: non-empty-string", "return: String"], declaration.contracts.map(&:payload)
    assert_equal ["Guaranteed by validation.", "Public return type."], declaration.contracts.map(&:note)
    assert_equal ["The stored value."], declaration.documentation.map(&:description)
  end

  def test_leaves_contract_note_nil_without_a_separator
    declaration = Zard.parse("# @rbs return: String\ndef call = \"value\"\n", path: "example.rb").declarations.fetch(0)

    assert_nil declaration.contracts.fetch(0).note
  end

  def test_continues_every_documentation_tag_until_the_next_annotation
    source = "# @param path — Path to read.  \n# Must be readable.\n#\n# Kept open while reading.\n# @example\n#   @value = reader.read\n#     puts @value\n# @return Result.\ndef read(path) = nil\n"
    document = Zard.parse(source, path: "example.rb")
    parameter, example, returned = document.declarations.fetch(0).documentation

    assert_empty document.diagnostics
    assert_equal "Path to read.  \nMust be readable.\n\nKept open while reading.", parameter.description
    assert_equal "  @value = reader.read\n    puts @value", example.description
    assert_equal "Result.", returned.description
    assert_equal 1, parameter.span.start_line
    assert_equal 4, parameter.span.end_line
  end

  def test_keeps_yard_like_continuation_raw
    source = "# @param value [String] YARD-like description.\n# Continued description.\ndef call(value) = value\n"
    document = Zard.parse(source, path: "example.rb")
    tag = document.declarations.fetch(0).documentation.fetch(0)

    assert_equal :raw, tag.name
    assert_equal "@param value [String] YARD-like description.\nContinued description.", tag.description
    assert_equal ["documentation.yard-like"], document.diagnostics.map(&:code)
  end

  def test_contract_ends_continuation_without_reconnecting_it
    source = "# @return Cached value.\n# @rbs return: String\n# Recomputed when stale.\ndef call = \"value\"\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal %i[return text], declaration.documentation.map(&:name)
    assert_equal ["Cached value.", "Recomputed when stale."], declaration.documentation.map(&:description)
  end

  def test_warns_about_an_empty_description
    document = Zard.parse("# @param value —\ndef call(value) = value\n", path: "example.rb")

    assert_equal "", document.declarations.fetch(0).documentation.fetch(0).description
    assert_equal ["documentation.empty-description"], document.diagnostics.map(&:code)
  end

  def test_preserves_crlf_raw_text_and_normalizes_description_newlines
    source = "# @note First.\r\n# Second.\r\ndef call = nil\r\n"
    tag = Zard.parse(source, path: "example.rb").declarations.fetch(0).documentation.fetch(0)

    assert_equal "First.\nSecond.", tag.description
    assert_equal "# @note First.\r\n# Second.\r", tag.raw
  end

  def test_keeps_noncanonical_documentation_tags_raw
    source = "#  @param value — Description.\n# Continued raw text.\ndef call(value) = value\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal [:raw], document.declarations.fetch(0).documentation.map(&:name)
    assert_equal ["documentation.noncanonical-spacing"], document.diagnostics.map(&:code)
  end
end
