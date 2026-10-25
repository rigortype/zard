# frozen_string_literal: true

require "test_helper"

class ParameterDetailsTest < Minitest::Test
  def parse(source)
    Zard.parse(source, path: "lib/example.rb")
  end

  def test_preserves_parameter_order_kinds_defaults_and_exact_source_spans
    source = <<~RUBY
      def call(first, second = [1,
        {key: "value"}], *rest, last, required:, optional: -> { raise "never execute" }, **options, &block)
      end
    RUBY
    document = parse(source)
    assert_empty document.diagnostics
    declaration = document.declarations.first
    assert_equal ["first", "second", "*rest", "last", "required:", "optional:", "**options", "&block"], declaration.parameters
    details = declaration.parameter_details
    assert_equal %i[required optional rest post required_keyword optional_keyword keyword_rest block], details.map(&:kind)
    assert_equal "[1,\n  {key: \"value\"}]", details[1].default
    assert_equal '-> { raise "never execute" }', details[5].default
    details.each do |parameter|
      location = parameter.span
      assert_equal parameter.source, source.byteslice(location.start_offset...location.end_offset)
      next unless parameter.default

      location = parameter.default_span
      assert_equal parameter.default, source.byteslice(location.start_offset...location.end_offset)
    end
    assert details.frozen?
    assert details.all?(&:frozen?)
  end

  def test_keeps_forwarding_anonymous_no_keyword_and_destructured_syntax
    source = <<~RUBY
      class Example
      def forward(...); end
      def anonymous(*, **, &); end
      def no_keywords(**nil); end
      def destructured((first, (second, third)), *rest, (last, tail)); end
      define_method(:block_method) { |item, optional = 1, **options| }
      end
    RUBY
    document = parse(source)
    assert_empty document.diagnostics
    forward, anonymous, no_keywords, destructured, block = document.declarations.drop(1)
    assert_equal [:forwarding], forward.parameter_details.map(&:kind)
    assert_equal ["..."], forward.parameter_details.map(&:source)
    assert_equal ["*", "**", "&"], anonymous.parameter_details.map(&:source)
    assert anonymous.parameter_details.all? { |parameter| parameter.name.nil? }
    assert_equal [:no_keywords], no_keywords.parameter_details.map(&:kind)
    assert_equal ["**nil"], no_keywords.parameter_details.map(&:source)
    assert_equal ["(first, (second, third))", "*rest", "(last, tail)"], destructured.parameter_details.map(&:source)
    assert_equal %i[required rest post], destructured.parameter_details.map(&:kind)
    assert_equal ["item", "optional = 1", "**options"], block.parameter_details.map(&:source)
  end

  def test_preserves_details_through_visibility_and_module_function_changes_without_fabricating_alias_parameters
    document = parse(<<~RUBY)
      module Example
        def call(value = 1); end
        private :call
        module_function :call
        alias another call
      end
    RUBY
    methods = document.declarations.select { |declaration| declaration.name == "call" }
    assert_equal %i[private public], methods.map(&:visibility)
    assert_equal [["value = 1"], ["value = 1"]], methods.map { |declaration| declaration.parameter_details.map(&:source) }
    assert_nil document.declarations.last.parameter_details
  end

  def test_diagnoses_noncontiguous_heredoc_defaults_instead_of_exporting_a_partial_default
    document = parse("def call(value = <<~TEXT)\n  hello\nTEXT\nend\n")
    parameter = document.declarations.first.parameter_details.first
    assert_equal "value = <<~TEXT", parameter.source
    assert_nil parameter.default
    assert_nil parameter.default_span
    assert_equal ["parameter.unsupported-default"], document.diagnostics.map(&:code)
  end

  def test_diagnoses_nested_heredoc_defaults_instead_of_exporting_a_partial_default
    document = parse("def call(value = [<<~TEXT]); end\n  hello\nTEXT\n")
    parameter = document.declarations.first.parameter_details.first
    assert_equal "value = [<<~TEXT]", parameter.source
    assert_nil parameter.default
    assert_nil parameter.default_span
    assert_equal ["parameter.unsupported-default"], document.diagnostics.map(&:code)
  end

  def test_diagnoses_implicit_block_parameters_without_inventing_a_method_signature
    document = parse("class Example; define_method(:numbered) { _1 }; define_singleton_method(:implicit) { it }; end")
    assert_equal ["Example"], document.declarations.map(&:name)
    assert_equal ["parameter.unsupported-form", "parameter.unsupported-form"], document.diagnostics.map(&:code)
  end
end
