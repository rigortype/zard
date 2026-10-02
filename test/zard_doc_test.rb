# frozen_string_literal: true

require "test_helper"
require "zard/doc"

class ZardDocTest < Minitest::Test
  def test_renders_the_first_vertical_slice_as_markdown
    ruby_path = File.expand_path("fixtures/read_name.rb", __dir__)
    markdown_path = File.expand_path("fixtures/read_name.md", __dir__)
    document = Zard.parse(File.read(ruby_path), path: ruby_path)

    assert_equal File.read(markdown_path), Zard::Doc.render(document)
  end

  def test_renders_yield_parameters_and_return_value
    source = "# @yieldparam value — Each value.\n# @yieldreturn The consumed length.\ndef each_value = yield(\"value\")\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## `each_value()`

      ### Yield parameters

      - `value` — Each value.

      ### Yields

      The consumed length.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end
end
