# frozen_string_literal: true

require "test_helper"

class FormatterTest < Minitest::Test
  def test_normalizes_extrbs_spacing_and_stable_order_without_changing_contract_text
    source = "# Heading.\n# @rbs return: String -- Public note.  \n\#@extrbs value: opaque -- Extended note.  \n#  @extrbs return: opaque\n# @return Value.\ndef call(value) = value\n"
    expected = "# Heading.\n# @extrbs value: opaque -- Extended note.  \n# @extrbs return: opaque\n# @rbs return: String -- Public note.  \n# @return Value.\ndef call(value) = value\n"
    result = Zard.format(source, path: "memory.rb")

    assert_equal expected, result.source
    assert result.changed?
    assert_empty result.diagnostics
    assert_equal ["value: opaque", "return: opaque", "return: String"], result.document.declarations.first.contracts.map(&:payload)
    assert_equal ["Extended note.  ", nil, "Public note.  "], result.document.declarations.first.contracts.map(&:note)
    refute Zard.format(result.source, path: "memory.rb").changed?
  end

  def test_removes_only_redundant_nameless_markers_and_preserves_continuations
    source = "# @return — Value.\n#   Details.  \n#\n# More.\n# @yieldreturn — Yielded.\n# @param value — Input.\ndef call(value) = value\n"
    original = Zard.parse(source, path: "memory.rb")
    result = Zard.format(source, path: "memory.rb")

    assert_equal source.sub("@return —", "@return").sub("@yieldreturn —", "@yieldreturn"), result.source
    assert_equal original.declarations.first.documentation.map(&:description), result.document.declarations.first.documentation.map(&:description)
    assert_empty result.diagnostics
    assert_equal result.source, Zard.format(result.source, path: "memory.rb").source
  end

  def test_moves_extrbs_past_a_complete_multiline_description_safely
    source = "# @note A.\n# Continued.\n# @extrbs return: opaque\ndef call = nil\n"
    result = Zard.format(source, path: "memory.rb")

    assert_equal "# @extrbs return: opaque\n# @note A.\n# Continued.\ndef call = nil\n", result.source
    assert_equal "A.\nContinued.", result.document.declarations.first.documentation.first.description
    assert_empty result.diagnostics
  end

  def test_rejects_reordering_that_changes_continuation_ownership
    source = "# @note A.\n# @extrbs return: opaque\n# Separate prose.\n# @return — Value.\ndef call = nil\n"
    result = Zard.format(source, path: "memory.rb")

    assert_equal source.sub("@return —", "@return"), result.source
    assert_equal ["extrbs.not-first", "format.unsafe-extrbs-order"], result.diagnostics.map(&:code)
    assert_equal [:note, :text, :return], result.document.declarations.first.documentation.map(&:name)
    assert_equal result.source, Zard.format(result.source, path: "memory.rb").source
  end

  def test_noncanonical_extrbs_with_continuations_is_ambiguous
    source = "#  @extrbs return: opaque\n# Continued raw text.\ndef call = nil\n"
    result = Zard.format(source, path: "memory.rb")

    assert_equal source, result.source
    refute result.changed?
    assert_equal ["extrbs.noncanonical-spacing"], result.diagnostics.map(&:code)
  end

  def test_leaves_yard_like_unknown_and_noncanonical_documentation_unchanged
    source = "# @param value [String] Text.\n# Continuation.\n# @unknown data\n#  @return — Text.\ndef call(value) = value\n"
    result = Zard.format(source, path: "memory.rb")

    assert_equal source, result.source
    assert_equal ["documentation.yard-like", "documentation.noncanonical-spacing"], result.diagnostics.map(&:code)
    assert_equal result.source, Zard.format(result.source, path: "memory.rb").source
  end

  def test_preserves_indentation_unicode_and_mixed_line_terminators
    source = "class Foo\r\n  # @rbs return: String\n  #\t@extrbs return: opaque\r\n  # @return — 日本語。  \n  def call = nil\r\nend"
    result = Zard.format(source.b, path: "memory.rb")

    assert_equal "class Foo\r\n  # @extrbs return: opaque\n  # @rbs return: String\r\n  # @return 日本語。  \n  def call = nil\r\nend".b, result.source
    assert_equal source.scan(/\r?\n/), result.source.scan(/\r?\n/)
    assert_equal "日本語。  ", result.document.declarations.find { |declaration| declaration.name == "call" }.documentation.first.description
    assert_equal result.source, Zard.format(result.source, path: "memory.rb").source
  end

  def test_preserves_strings_embedded_documents_detached_and_inline_comments
    source = "text = \"#  @extrbs value: opaque\"\n=begin\n# @return — Value.\n=end\n\#@extrbs detached: opaque\n\ndef call = nil # @return — Inline.\n"
    result = Zard.format(source, path: "memory.rb")

    assert_equal source, result.source
    refute result.changed?
  end

  def test_preserves_example_content
    source = "# @example\n# ```ruby\n#   @return — Literal.\n# ```\ndef call = nil\n"
    assert_equal source, Zard.format(source, path: "memory.rb").source
    source = "# @example\n#   @extrbs value: opaque\ndef call = nil\n"
    assert_equal source, Zard.format(source, path: "memory.rb").source
  end

  def test_reparses_raw_text_and_byte_spans_against_the_returned_source
    source = "# @return — 値。\n# @extrbs return: opaque\ndef call = nil\n"
    result = Zard.format(source, path: "memory.rb")
    declaration = result.document.declarations.first
    (declaration.contracts + declaration.documentation).each do |item|
      assert_equal item.raw.b, result.source.byteslice(item.span.start_offset, item.span.end_offset - item.span.start_offset).b
      assert_equal "memory.rb", item.span.path
    end
    assert_equal 1, declaration.contracts.first.span.start_line
    assert_equal 2, declaration.documentation.first.span.start_line
    assert_equal "# @return — 値。\n# @extrbs return: opaque\ndef call = nil\n", source
    assert result.source.frozen?
    assert result.frozen?
  end

  def test_returns_invalid_ruby_unchanged_with_errors
    source = "# @return — Value.\ndef call(\n"
    result = Zard.format(source, path: "memory.rb")

    assert_equal source, result.source
    refute result.changed?
    assert result.diagnostics.any? { |diagnostic| diagnostic.code == "ruby.syntax" }
  end

  def test_reports_non_utf8_source_without_editing_contracts
    source = "# coding: us-ascii\n\#@extrbs value: opaque\ndef call = nil\n"
    result = Zard.format(source, path: "memory.rb")

    assert_equal source, result.source
    refute result.changed?
    assert_equal ["extrbs.noncanonical-spacing", "format.unsupported-encoding"], result.diagnostics.map(&:code)
  end

  def test_empty_source_is_unchanged
    result = Zard.format("", path: "memory.rb")

    assert_equal "", result.source
    refute result.changed?
    assert_empty result.document.declarations
    assert_empty result.diagnostics
  end

  def test_marker_removal_cannot_turn_description_text_into_a_claim_or_another_marker
    ["[opaque] — Description.", "— Description.", "[unclosed"].each do |description|
      source = "# @return — #{description}\ndef call = nil\n"
      result = Zard.format(source, path: "memory.rb")

      assert_equal source, result.source
      assert_nil result.document.declarations.first.documentation.first.claim
      assert_equal description, result.document.declarations.first.documentation.first.description
      assert_equal source, Zard.format(result.source, path: "memory.rb").source
    end
  end

  def test_protects_canonical_annotations_inside_fenced_examples
    source = "# @example\n# ```ruby\n# @return — Literal.\n# @extrbs literal: opaque\n# ```\ndef call = nil\n"

    assert_equal source, Zard.format(source, path: "memory.rb").source
    source = "# @example\n\#@extrbs first: opaque\n\#@extrbs second: opaque\ndef call = nil\n"
    assert_equal source, Zard.format(source, path: "memory.rb").source
    source = "# @example ```ruby\n# @return — Literal.\n# @extrbs literal: opaque\n# ```\ndef call = nil\n"
    assert_equal source, Zard.format(source, path: "memory.rb").source
    source = "# @example ```ruby\n# @note ```\n# @return — Literal.\n# ```\ndef call = nil\n"
    assert_equal source, Zard.format(source, path: "memory.rb").source
  end

  def test_invalid_source_encoding_returns_errors_instead_of_raising
    ["# text \xFF\n\#@extrbs value: opaque\ndef call = nil\n".b, "def call = nil\n".encode("UTF-16LE")].each do |source|
      result = Zard.format(source, path: "memory.rb")

      assert_equal source, result.source
      refute result.changed?
      assert_equal :error, result.diagnostics.first.severity
      assert_equal "memory.rb", result.diagnostics.first.span.path
      assert_empty result.document.declarations
    end
  end
end
