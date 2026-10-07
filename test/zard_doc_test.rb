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

  def test_renders_documented_modules_classes_and_methods
    source = "# Public API.\nmodule Demo\n  # Reads stored values.\n  class Reader\n    # @return Stored value.\n    def read = nil\n  end\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Module `Demo`

      Public API.

      ## Class `Demo::Reader`

      Reads stored values.

      ## `Demo::Reader#read()`

      ### Returns

      Stored value.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_documented_constants
    source = "module Demo\n  # Default retry limit.\n  RETRY_LIMIT = 3\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Constant `Demo::RETRY_LIMIT`

      Default retry limit.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_class_builders_and_their_block_members
    source = "# Pair values.\nPair = Data.define(:left, :right) do\n  # Returns both values.\n  def values = [left, right]\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Class `Pair`

      Class builder: `Data.define(:left, :right)`.

      Pair values.

      ## `Pair#values()`

      Returns both values.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_a_multiline_class_builder_as_a_code_block
    source = "module Models\n  # Pair values.\n  Pair = Data.define(\n    :left,\n    :right\n  )\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Class `Models::Pair`

      Class builder:

      ```ruby
      Data.define(
        :left,
        :right
      )
      ```

      Pair values.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_a_class_new_builder_and_its_members
    source = "# Record API.\nRecord = Class.new(BaseRecord) do\n  include Enumerable\n  # Visits each value.\n  def each = nil\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Class `Record`

      Class builder: `Class.new(BaseRecord)`.

      ### Includes

      - `Enumerable`

      Record API.

      ## `Record#each()`

      Visits each value.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_a_module_new_builder_and_its_members
    source = "# Shared helpers.\nHelpers = Module.new do\n  include Enumerable\n  # Visits each value.\n  def each = nil\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Module `Helpers`

      Module builder: `Module.new`.

      ### Includes

      - `Enumerable`

      Shared helpers.

      ## `Helpers#each()`

      Visits each value.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_a_conditionally_initialized_module_builder
    source = "# Shared helpers.\nHelpers ||= Module.new do\n  # Visits each value.\n  def each = nil\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Module `Helpers`

      Module builder: `Module.new`.

      Shared helpers.

      ## `Helpers#each()`

      Visits each value.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_a_delegate_class_builder
    source = "# Wrapper API.\nWrapper = DelegateClass(Target)\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Class `Wrapper`

      Class builder: `DelegateClass(Target)`.

      Wrapper API.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_a_module_builder_behind_a_freeze_tail
    source = "# Shared helpers.\nHelpers = Module.new do\n  # Visits each value.\n  def each = nil\nend.freeze\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Module `Helpers`

      Module builder: `Module.new`.

      Shared helpers.

      ## `Helpers#each()`

      Visits each value.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_a_module_builder_behind_a_self_referential_or_guard
    source = "# Shared helpers.\nHelpers = Helpers || Module.new.freeze\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Module `Helpers`

      Module builder: `Module.new`.

      Shared helpers.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_instance_and_singleton_attributes
    source = "class Reader\n  # Stored name.\n  attr_reader :name\n  class << self\n    # Current format version.\n    attr_accessor :version\n  end\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Attribute reader `Reader#name`

      Stored name.

      ## Attribute accessor `Reader.version`

      Current format version.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_explicit_singleton_receivers
    source = "# Builds a reader.\ndef Registry.build = nil\nclass Reader\n  class << Registry\n    # Current version.\n    attr_reader :version\n  end\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## `Registry.build()`

      Builds a reader.

      ## Attribute reader `Registry.version`

      Current version.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_refinements_separately_from_enclosing_module_members
    source = "module TextExtensions\n  # String helpers.\n  refine String do\n    # Returns a tagged copy.\n    def tagged = self\n  end\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Refinement `TextExtensions[String]`

      String helpers.

      ## `TextExtensions[String]#tagged()`

      Returns a tagged copy.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_methods_declared_by_method_definition_calls
    source = "class Reader\n  # Reads a value.\n  define_method(:read) { |path| path }\nend\n# Builds a reader.\nRegistry.define_singleton_method(:build) { |path| path }\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## `Reader#read(path)`

      Reads a value.

      ## `Registry.build(path)`

      Builds a reader.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_only_public_declarations
    source = "class Reader\n  # Visible API.\n  def visible = nil\n  private\n  # Internal helper.\n  def hidden = nil\n  # Internal state.\n  attr_reader :token\n  public\n  # Public state.\n  attr_reader :name\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## `Reader#visible()`

      Visible API.

      ## Attribute reader `Reader#name`

      Public state.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_hides_methods_made_private_by_name
    source = "class Reader\n  # Internal helper.\n  def hidden = nil\n  private :hidden\nend\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal "", Zard::Doc.render(document)
  end

  def test_hides_private_class_methods
    source = "class Reader\n  # Internal constructor.\n  def self.build = new\n  private_class_method :build\nend\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal "", Zard::Doc.render(document)
  end

  def test_renders_the_public_module_function_copy
    source = "module Helpers\n  # Normalizes a name.\n  module_function def normalize(name) = name.strip\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## `Helpers.normalize(name)`

      Normalizes a name.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_a_documented_method_alias_without_copying_target_documentation
    source = "class Reader\n  # Reads a path.\n  def read(path) = path\n  # Compatibility name.\n  alias fetch read\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## `Reader#read(path)`

      Reads a path.

      ## Alias `Reader#fetch`

      Alias of `Reader#read`.

      Compatibility name.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_an_explicit_superclass
    source = "# Reads stored values.\nclass Reader < BaseReader\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Class `Reader`

      Superclass: `BaseReader`.

      Reads stored values.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_a_named_data_subclass_without_recasting_its_superclass
    source = "# Pair values.\nclass Pair < Data.define(:left, :right)\n  # Returns both values.\n  def values = [left, right]\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Class `Pair`

      Superclass: `Data.define(:left, :right)`.

      Pair values.

      ## `Pair#values()`

      Returns both values.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_mixin_references_on_a_documented_container
    source = "# Reads values.\nclass Reader\n  include Enumerable, Readable\n  prepend Instrumentation\n  extend FactoryMethods\nend\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## Class `Reader`

      ### Includes

      - `Enumerable`
      - `Readable`

      ### Prepends

      - `Instrumentation`

      ### Extends

      - `FactoryMethods`

      Reads values.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_hides_private_constants_and_classes
    source = "module Demo\n  # Internal value.\n  VALUE = 1\n  # Internal implementation.\n  class Internal\n  end\n  private_constant :VALUE, :Internal\nend\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal "", Zard::Doc.render(document)
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

  def test_renders_options_and_raised_exceptions
    source = "# @option options :format — Output format.\n# @option options :limit [Integer] — Maximum count.\n# @raise IOError — If the input cannot be read.\ndef read(**options) = nil\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## `read(**options)`

      ### Options for `options`

      - `:format` — Output format.
      - `:limit` — Maximum count.

      ### Raises

      - `IOError` — If the input cannot be read.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_renders_description_only_tags
    source = "# @note Thread-safe after initialization.\n# @see https://example.test/reference\n# @deprecated Use #fetch instead.\n# @example reader.read\ndef read = nil\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## `read()`

      ### Deprecated

      Use #fetch instead.

      ### Notes

      Thread-safe after initialization.

      ### Examples

      reader.read

      ### See also

      - https://example.test/reference
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end

  def test_does_not_render_contract_notes_as_api_documentation
    source = "# @extrbs return: non-empty-string -- Guaranteed by validation.\n# @return The stored value.\ndef call = \"value\"\n"
    document = Zard.parse(source, path: "example.rb")

    assert_equal "## `call()`\n\n### Returns\n\nThe stored value.\n", Zard::Doc.render(document)
  end

  def test_renders_multiline_descriptions_inside_list_items
    source = "# @param path — Path to read.\n# Must be readable.\n#\n# Kept open while reading.\n# @see Reader#read\n# Additional details.\ndef read(path) = nil\n"
    document = Zard.parse(source, path: "example.rb")
    expected = <<~MARKDOWN
      ## `read(path)`

      ### Parameters

      - `path` — Path to read.
        Must be readable.

        Kept open while reading.

      ### See also

      - Reader#read
        Additional details.
    MARKDOWN

    assert_equal expected, Zard::Doc.render(document)
  end
end
