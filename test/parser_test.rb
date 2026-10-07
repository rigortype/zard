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

  def test_collects_literal_autoload_declarations
    source = "# Lazy root API.\nself.autoload \"RootApi\", \"root_api\"\nmodule Models\n  # Lazy widget API.\n  self.autoload :Widget, \"models/widget\"\n  autoload :Hidden, path_for(:hidden)\n  private_constant :Hidden\nend\n"
    root, models, widget, hidden = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:constant, :module, :constant, :constant], [root, models, widget, hidden].map(&:kind)
    assert_equal [nil, nil, "Models", "Models"], [root, models, widget, hidden].map(&:namespace)
    assert_equal [:public, :public, :public, :private], [root, models, widget, hidden].map(&:visibility)
    assert_equal ["Lazy root API.", "Lazy widget API."], [root, widget].map { |declaration| declaration.documentation.fetch(0).description }
  end

  def test_ignores_dynamic_received_and_method_body_autoload_calls
    source = "autoload NAME, \"dynamic\"\nRegistry.autoload :Remote, \"remote\"\nmodule Models\n  class << self\n    autoload :SingletonOwned, \"singleton_owned\"\n  end\n  refine String do\n    self.autoload :Refined, \"refined\"\n  end\nend\ndef configure\n  autoload :Nested, \"nested\"\nend\n"
    declarations = Zard.parse(source, path: "example.rb").declarations

    assert_equal [[:module, "Models"], [:refinement, "String"], [:instance_method, "configure"]], declarations.map { |declaration| [declaration.kind, declaration.name] }
  end

  def test_collects_literal_const_set_declarations_in_the_current_container
    source = "module Models\n  # Default limit.\n  const_set :LIMIT, 3\n  # Record API.\n  self.const_set(:Record, Data.define(:name))\n  private_constant :LIMIT\nend\n"
    models, limit, record, name = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:module, :constant, :class, :instance_attribute_reader], [models, limit, record, name].map(&:kind)
    assert_equal ["Models", "Models", "Models::Record"], [limit.namespace, record.namespace, name.namespace]
    assert_equal [:private, :public, :public], [limit.visibility, record.visibility, name.visibility]
    assert_equal "Data.define(:name)", record.container_builder
    assert_equal ["Default limit.", "Record API."], [limit, record].map { |declaration| declaration.documentation.fetch(0).description }
  end

  def test_ignores_const_set_when_the_owner_is_not_the_current_ordinary_container
    source = "const_set(:Root, 1)\nmodule Models\n  Registry.const_set(:Remote, 1)\n  const_set(NAME, 1)\n  class << self\n    const_set(:SingletonOwned, 1)\n  end\n  refine String do\n    const_set(:Refined, 1)\n  end\n  def configure\n    const_set(:Nested, 1)\n  end\nend\n"
    declarations = Zard.parse(source, path: "example.rb").declarations

    assert_equal [[:module, "Models"], [:refinement, "String"], [:instance_method, "configure"]], declarations.map { |declaration| [declaration.kind, declaration.name] }
  end

  def test_models_container_builders_used_for_conditional_constant_initialization
    source = "# Registry API.\nRegistry ||= Class.new do\n  def fetch = nil\nend\nmodule Models\n  # Shared helpers.\n  Helpers ||= Module.new do\n    include Enumerable\n  end\nend\n"
    registry, fetch, models, helpers = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:class, :instance_method, :module, :module], [registry, fetch, models, helpers].map(&:kind)
    assert_equal ["Class.new", "Module.new"], [registry.container_builder, helpers.container_builder]
    assert_equal [nil, "Registry", nil, "Models"], [registry.namespace, fetch.namespace, models.namespace, helpers.namespace]
    assert_equal [[:include, "Enumerable"]], helpers.mixins.map { |mixin| [mixin.kind, mixin.target] }
    assert_equal ["Registry API.", "Shared helpers."], [registry, helpers].map { |declaration| declaration.documentation.fetch(0).description }
  end

  def test_models_qualified_container_builder_conditional_initialization
    source = "# Shared helpers.\nModels::Helpers ||= Module.new\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal :module, declaration.kind
    assert_equal "Helpers", declaration.name
    assert_equal "Models", declaration.namespace
    assert_equal "Module.new", declaration.container_builder
  end

  def test_models_data_define_as_a_class_with_readers_and_block_members
    source = "# Pair values.\nPair = Data.define(:left, :right) do\n  # Returns both values.\n  def values = [left, right]\nend\n"
    klass, left, right, values = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:class, :instance_attribute_reader, :instance_attribute_reader, :instance_method], [klass, left, right, values].map(&:kind)
    assert_equal [nil, "Pair", "Pair", "Pair"], [klass, left, right, values].map(&:namespace)
    assert_equal "Data.define(:left, :right)", klass.container_builder
    assert_equal klass.container_builder, source.byteslice(klass.container_builder_span.start_offset...klass.container_builder_span.end_offset)
    assert_equal "Pair values.", klass.documentation.fetch(0).description
    assert_empty left.documentation
    assert_equal "Returns both values.", values.documentation.fetch(0).description
  end

  def test_models_struct_new_as_a_class_with_accessors
    source = "module Models\n  Point = Struct.new(:x, :y, keyword_init: true)\nend\n"
    mod, klass, x, y = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:module, :class, :instance_attribute_accessor, :instance_attribute_accessor], [mod, klass, x, y].map(&:kind)
    assert_equal [nil, "Models", "Models::Point", "Models::Point"], [mod, klass, x, y].map(&:namespace)
    assert_equal "Struct.new(:x, :y, keyword_init: true)", klass.container_builder
  end

  def test_does_not_invent_attributes_for_dynamic_class_builder_members
    source = "Record = Data.define(*MEMBERS) do\n  def value = nil\nend\n"
    declarations = Zard.parse(source, path: "example.rb").declarations

    assert_equal [[:class, "Record"], [:instance_method, "value"]], declarations.map { |declaration| [declaration.kind, declaration.name] }
    assert_equal "Record", declarations.fetch(1).namespace
  end

  def test_models_generated_attributes_on_named_data_subclasses
    source = "class Pair < Data.define(:left, :right)\n  def values = [left, right]\nend\n"
    klass, left, right, values = Zard.parse(source, path: "example.rb").declarations

    assert_equal "Data.define(:left, :right)", klass.superclass
    assert_nil klass.container_builder
    assert_equal [:instance_attribute_reader, :instance_attribute_reader], [left.kind, right.kind]
    assert_equal ["Pair", "Pair", "Pair"], [left.namespace, right.namespace, values.namespace]
  end

  def test_models_generated_attributes_on_named_struct_subclasses
    source = "module Models\n  class Point < Struct.new(:x, :y, keyword_init: true)\n  end\nend\n"
    declarations = Zard.parse(source, path: "example.rb").declarations
    klass = declarations.find { |declaration| declaration.kind == :class }
    attributes = declarations.select { |declaration| declaration.kind == :instance_attribute_accessor }

    assert_equal "Struct.new(:x, :y, keyword_init: true)", klass.superclass
    assert_equal ["x", "y"], attributes.map(&:name)
    assert_equal ["Models::Point", "Models::Point"], attributes.map(&:namespace)
  end

  def test_does_not_invent_attributes_on_a_dynamic_named_data_subclass
    source = "class Record < Data.define(*MEMBERS)\n  def value = nil\nend\n"
    declarations = Zard.parse(source, path: "example.rb").declarations

    assert_equal [[:class, "Record"], [:instance_method, "value"]], declarations.map { |declaration| [declaration.kind, declaration.name] }
  end

  def test_models_class_new_as_a_class_with_block_members
    source = "module Models\n  Record = Class.new(BaseRecord) do\n    include Enumerable\n    VALUE = 1\n    def each = nil\n  end\nend\n"
    mod, klass, value, each = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:module, :class, :constant, :instance_method], [mod, klass, value, each].map(&:kind)
    assert_equal "Class.new(BaseRecord)", klass.container_builder
    assert_equal ["Models", "Models::Record", "Models::Record"], [klass.namespace, value.namespace, each.namespace]
    assert_equal [[:include, "Enumerable"]], klass.mixins.map { |mixin| [mixin.kind, mixin.target] }
  end

  def test_models_a_class_new_assignment_without_a_block
    source = "Error = Class.new(StandardError)\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal :class, declaration.kind
    assert_equal "Error", declaration.name
    assert_equal "Class.new(StandardError)", declaration.container_builder
  end

  def test_models_module_new_as_a_module_with_block_members
    source = "module Models\n  Helpers = Module.new do\n    include Enumerable\n    VALUE = 1\n    def each = nil\n  end\nend\n"
    outer, mod, value, each = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:module, :module, :constant, :instance_method], [outer, mod, value, each].map(&:kind)
    assert_equal "Module.new", mod.container_builder
    assert_equal ["Models", "Models::Helpers", "Models::Helpers"], [mod.namespace, value.namespace, each.namespace]
    assert_equal [[:include, "Enumerable"]], mod.mixins.map { |mixin| [mixin.kind, mixin.target] }
  end

  def test_models_a_module_new_assignment_without_a_block
    declaration = Zard.parse("Helpers = Module.new\n", path: "example.rb").declarations.fetch(0)

    assert_equal :module, declaration.kind
    assert_equal "Helpers", declaration.name
    assert_equal "Module.new", declaration.container_builder
  end

  def test_models_delegate_class_assignments_as_classes
    source = "# Wrapper API.\nWrapper = DelegateClass(Target)\nFallback ||= DelegateClass(Base)\n"
    wrapper, fallback = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:class, :class], [wrapper.kind, fallback.kind]
    assert_equal ["Wrapper", "Fallback"], [wrapper.name, fallback.name]
    assert_equal ["DelegateClass(Target)", "DelegateClass(Base)"], [wrapper.container_builder, fallback.container_builder]
    assert_equal wrapper.container_builder, source.byteslice(wrapper.container_builder_span.start_offset...wrapper.container_builder_span.end_offset)
    assert_equal "Wrapper API.", wrapper.documentation.fetch(0).description
  end

  def test_preserves_delegate_class_as_a_named_subclass_superclass
    source = "class Wrapper < DelegateClass(Target)\nend\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal :class, declaration.kind
    assert_equal "DelegateClass(Target)", declaration.superclass
    assert_nil declaration.container_builder
  end

  def test_models_container_builders_behind_freeze_tails
    source = "Record = Data.define(:name).freeze\nHelpers = Module.new do\n  include Enumerable\n  def each = nil\nend.freeze.freeze\n"
    record, name, helpers, each = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:class, :instance_attribute_reader, :module, :instance_method], [record, name, helpers, each].map(&:kind)
    assert_equal ["Data.define(:name)", "Module.new"], [record.container_builder, helpers.container_builder]
    assert_equal ["Record", "Helpers"], [name.namespace, each.namespace]
    assert_equal [[:include, "Enumerable"]], helpers.mixins.map { |mixin| [mixin.kind, mixin.target] }
  end

  def test_does_not_unwrap_noncanonical_freeze_tails
    source = "Safe = Module.new&.freeze\nArgument = Module.new.freeze(:later)\nBlocked = Module.new.freeze {}\n"
    declarations = Zard.parse(source, path: "example.rb").declarations

    assert_equal [[:constant, "Safe"], [:constant, "Argument"], [:constant, "Blocked"]], declarations.map { |declaration| [declaration.kind, declaration.name] }
    assert declarations.all? { |declaration| declaration.container_builder.nil? }
  end

  def test_models_container_builders_behind_self_referential_or_guards
    source = "Registry = Registry || Class.new\nModels::Helpers = ::Models::Helpers || Module.new.freeze\n"
    registry, helpers = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:class, :module], [registry.kind, helpers.kind]
    assert_equal ["Registry", "Helpers"], [registry.name, helpers.name]
    assert_equal [nil, "Models"], [registry.namespace, helpers.namespace]
    assert_equal ["Class.new", "Module.new"], [registry.container_builder, helpers.container_builder]
  end

  def test_does_not_unwrap_or_guards_for_different_or_dynamic_constants
    source = "Current = Other || Module.new\nself::Dynamic = self::Dynamic || Class.new\n"
    declarations = Zard.parse(source, path: "example.rb").declarations

    assert_equal [[:constant, "Current"], [:constant, "Dynamic"]], declarations.map { |declaration| [declaration.kind, declaration.name] }
    assert declarations.all? { |declaration| declaration.container_builder.nil? }
  end

  def test_models_generated_attributes_inherited_through_class_new
    source = "Record = Class.new(Struct.new(:name, :age)) do\n  def label = name\nend\nPoint = Class.new(Class.new(Data.define(:x)))\n"
    record, name, age, label, point, x = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:class, :instance_attribute_accessor, :instance_attribute_accessor, :instance_method], [record, name, age, label].map(&:kind)
    assert_equal [:class, :instance_attribute_reader], [point.kind, x.kind]
    assert_equal ["Record", "Record", "Record"], [name.namespace, age.namespace, label.namespace]
    assert_equal "Point", x.namespace
    assert_equal ["Class.new(Struct.new(:name, :age))", "Class.new(Class.new(Data.define(:x)))"], [record.container_builder, point.container_builder]
  end

  def test_does_not_move_attributes_through_nested_factory_blocks
    source = "Outer = Class.new(Struct.new(:x) do\n  def x = nil\nend)\nNested = Class.new(Class.new(Data.define(:y)) do\nend)\n"
    declarations = Zard.parse(source, path: "example.rb").declarations

    assert_equal [[:class, "Outer"], [:class, "Nested"]], declarations.map { |declaration| [declaration.kind, declaration.name] }
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

  def test_collects_attr_readers_and_legacy_writable_attributes
    source = "class Reader\n  # Stored values.\n  attr :name, :format\n  attr(:token, true)\n  private attr(:secret, false)\n  class << self\n    attr :version\n  end\nend\n"
    attributes = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind.to_s.include?("attribute") }

    assert_equal %i[instance_attribute_reader instance_attribute_reader instance_attribute_accessor instance_attribute_reader singleton_attribute_reader], attributes.map(&:kind)
    assert_equal ["name", "format", "token", "secret", "version"], attributes.map(&:name)
    assert_equal %i[public public public private public], attributes.map(&:visibility)
    assert_equal ["Stored values.", "Stored values."], attributes.first(2).map { |declaration| declaration.documentation.fetch(0).description }
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

  def test_preserves_direct_and_singleton_class_receiver_references
    source = "# Builds a reader.\ndef Registry.build = nil\nclass Reader\n  class << Registry\n    # Current version.\n    attr_reader :version\n  end\nend\n"
    build, reader, version = Zard.parse(source, path: "example.rb").declarations

    assert_equal ["Registry", nil, "Registry"], [build.receiver, reader.receiver, version.receiver]
    assert_equal "Registry", source.byteslice(build.receiver_span.start_offset...build.receiver_span.end_offset)
    assert_equal "Registry", source.byteslice(version.receiver_span.start_offset...version.receiver_span.end_offset)
    assert_equal [nil, nil, "Reader"], [build.namespace, reader.namespace, version.namespace]
  end

  def test_preserves_self_as_a_singleton_receiver
    source = "class Reader\n  def self.build = new\n  class << self\n    def version = 1\n  end\nend\n"
    methods = Zard.parse(source, path: "example.rb").declarations.select { |declaration| declaration.kind == :singleton_method }

    assert_equal ["self", "self"], methods.map(&:receiver)
    assert_equal ["Reader", "Reader"], methods.map(&:namespace)
  end

  def test_keeps_alias_resolution_and_visibility_inside_the_receiver_scope
    source = "class Reader\n  class << First\n    def call = nil\n  end\n  class << Second\n    alias invoke call\n    private :call\n  end\nend\n"
    document = Zard.parse(source, path: "example.rb")
    call = document.declarations.find { |declaration| declaration.name == "call" }
    invoke = document.declarations.find { |declaration| declaration.name == "invoke" }

    assert_equal :public, call.visibility
    assert_equal "First", call.receiver
    assert_equal "Second", invoke.receiver
    assert_equal ["alias.unresolved-target"], document.diagnostics.map(&:code)
  end

  def test_preserves_refinements_and_keeps_their_members_in_a_separate_scope
    source = "module TextExtensions\n  # String helpers.\n  refine String do\n    # Returns a tagged copy.\n    def tagged = self\n    private\n    def internal = self\n  end\n  def ordinary = nil\nend\n"
    mod, refinement, tagged, internal, ordinary = Zard.parse(source, path: "example.rb").declarations

    assert_equal [:module, :refinement, :instance_method, :instance_method, :instance_method], [mod, refinement, tagged, internal, ordinary].map(&:kind)
    assert_equal "String", refinement.name
    assert_equal ["String", "String", nil], [tagged.refinement, internal.refinement, ordinary.refinement]
    assert_equal [:public, :private, :public], [tagged.visibility, internal.visibility, ordinary.visibility]
    assert_equal "String", source.byteslice(tagged.refinement_span.start_offset...tagged.refinement_span.end_offset)
  end

  def test_keeps_alias_resolution_inside_the_refinement_scope
    source = "module Extensions\n  refine String do\n    def call = nil\n  end\n  refine Array do\n    alias invoke call\n  end\nend\n"
    document = Zard.parse(source, path: "example.rb")
    invoke = document.declarations.find { |declaration| declaration.name == "invoke" }

    assert_equal "Array", invoke.refinement
    assert_equal ["alias.unresolved-target"], document.diagnostics.map(&:code)
  end

  def test_does_not_carry_a_refinement_scope_into_a_nested_class
    source = "module Extensions\n  refine String do\n    class Helper\n      def call = nil\n    end\n  end\nend\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.find { |item| item.name == "call" }

    assert_nil declaration.refinement
    assert_equal "Extensions::Helper", declaration.namespace
  end

  def test_collects_literal_define_method_calls_with_block_parameters
    source = "class Reader\n  # Reads a value.\n  define_method(:read) { |path, mode: :text, **options, &block| path }\n  class << self\n    define_method(\"version\") { 1 }\n  end\nend\n"
    methods = Zard.parse(source, path: "example.rb").declarations.select { |declaration| declaration.kind.to_s.end_with?("method") }

    assert_equal [[:instance_method, "read"], [:singleton_method, "version"]], methods.map { |declaration| [declaration.kind, declaration.name] }
    assert_equal ["path", "mode:", "**options", "&block"], methods.fetch(0).parameters
    assert_equal "Reads a value.", methods.fetch(0).documentation.fetch(0).description
    assert_equal "self", methods.fetch(1).receiver
  end

  def test_preserves_destructured_define_method_parameters
    source = "class Pair\n  define_method(:each_pair) { |(left, right)| [left, right] }\nend\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.find { |item| item.name == "each_pair" }

    assert_equal ["(left, right)"], declaration.parameters
  end

  def test_collects_received_define_singleton_method_calls
    source = "# Builds a reader.\nRegistry.define_singleton_method(:build) { |path| path }\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal :singleton_method, declaration.kind
    assert_equal "build", declaration.name
    assert_equal "Registry", declaration.receiver
    assert_equal ["path"], declaration.parameters
    assert_equal "Registry", source.byteslice(declaration.receiver_span.start_offset...declaration.receiver_span.end_offset)
  end

  def test_collects_a_top_level_define_singleton_method_call
    declaration = Zard.parse("define_singleton_method(:call) { nil }\n", path: "example.rb").declarations.fetch(0)

    assert_equal :singleton_method, declaration.kind
    assert_equal "self", declaration.receiver
    assert_nil declaration.namespace
  end

  def test_applies_module_function_mode_to_define_method
    source = "module Helpers\n  module_function\n  define_method(:normalize) { |value| value }\nend\n"
    methods = Zard.parse(source, path: "example.rb").declarations.select { |declaration| declaration.kind.to_s.end_with?("method") }

    assert_equal [[:instance_method, :private], [:singleton_method, :public]], methods.map { |declaration| [declaration.kind, declaration.visibility] }
  end

  def test_keeps_define_method_bodies_out_of_the_declaration_dsl
    source = "class Reader\n  define_method(method_name) do\n    private\n    attr_reader :ghost\n  end\n  def visible = nil\nend\n"
    document = Zard.parse(source, path: "example.rb")
    methods = document.declarations.select { |declaration| declaration.kind.to_s.end_with?("method") }
    attributes = document.declarations.select { |declaration| declaration.kind.to_s.include?("attribute") }

    assert_equal ["visible"], methods.map(&:name)
    assert_equal [:public], methods.map(&:visibility)
    assert_empty attributes
  end

  def test_keeps_define_method_inside_the_refinement_scope
    source = "module Extensions\n  refine String do\n    define_method(:tagged) { self }\n  end\nend\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.find { |item| item.name == "tagged" }

    assert_equal "String", declaration.refinement
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

  def test_applies_named_method_visibility_without_changing_the_default
    source = "class Reader\n  def old = nil\n  private :old\n  def current = nil\n  class << self\n    def version = nil\n    private :version\n  end\nend\n"
    methods = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind.to_s.end_with?("method") }

    assert_equal [
      ["old", :private],
      ["current", :public],
      ["version", :private]
    ], methods.map { |declaration| [declaration.name, declaration.visibility] }
  end

  def test_conservatively_applies_named_nonpublic_visibility_to_attributes
    source = "class Reader\n  attr_accessor :name\n  private :name\nend\n"
    document = Zard.parse(source, path: "example.rb")
    attribute = document.declarations.find { |declaration| declaration.kind == :instance_attribute_accessor }

    assert_equal :private, attribute.visibility
    assert_equal ["visibility.named-attribute"], document.diagnostics.map(&:code)
  end

  def test_does_not_guess_named_public_visibility_for_an_attribute
    source = "class Reader\n  private attr_accessor :name\n  public :name\nend\n"
    document = Zard.parse(source, path: "example.rb")
    attribute = document.declarations.find { |declaration| declaration.kind == :instance_attribute_accessor }

    assert_equal :private, attribute.visibility
    assert_equal ["visibility.named-attribute"], document.diagnostics.map(&:code)
  end

  def test_applies_named_and_inline_class_method_visibility
    source = "class Reader\n  def self.hidden = nil\n  private_class_method :hidden\n  private_class_method def self.inline = nil\n  def self.shown = nil\n  private_class_method :shown\n  public_class_method \"shown\"\nend\n"
    methods = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind == :singleton_method }

    assert_equal [
      ["hidden", :private],
      ["inline", :private],
      ["shown", :public]
    ], methods.map { |declaration| [declaration.name, declaration.visibility] }
  end

  def test_applies_class_method_visibility_to_singleton_class_methods
    source = "class Reader\n  class << self\n    def hidden = nil\n  end\n  private_class_method :hidden\nend\n"
    method = Zard.parse(source, path: "example.rb").declarations
      .find { |declaration| declaration.kind == :singleton_method }

    assert_equal :private, method.visibility
  end

  def test_models_bare_named_and_inline_module_functions
    source = "module Helpers\n  module_function\n  def first = nil\n  public\n  def second = nil\n  module_function :second\n  module_function def third = nil\nend\n"
    methods = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind.to_s.end_with?("method") }

    assert_equal [
      [:instance_method, "first", :private],
      [:singleton_method, "first", :public],
      [:instance_method, "second", :private],
      [:singleton_method, "second", :public],
      [:instance_method, "third", :private],
      [:singleton_method, "third", :public]
    ], methods.map { |declaration| [declaration.kind, declaration.name, declaration.visibility] }
  end

  def test_bare_visibility_ends_module_function_mode
    source = "module Helpers\n  module_function\n  def copied = nil\n  protected\n  def inherited = nil\nend\n"
    methods = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind.to_s.end_with?("method") }

    assert_equal [
      [:instance_method, "copied", :private],
      [:singleton_method, "copied", :public],
      [:instance_method, "inherited", :protected]
    ], methods.map { |declaration| [declaration.kind, declaration.name, declaration.visibility] }
  end

  def test_ignores_module_function_mode_in_classes
    source = "class Helpers\n  module_function\n  def visible = nil\nend\n"
    method = Zard.parse(source, path: "example.rb").declarations
      .find { |declaration| declaration.kind == :instance_method }

    assert_equal :public, method.visibility
  end

  def test_collects_alias_and_alias_method_with_target_metadata
    source = "class Reader\n  private\n  def read(path) = path\n  public\n  # Fetches a path.\n  alias fetch read\n  # Loads a path.\n  alias_method :load, :read\nend\n"
    document = Zard.parse(source, path: "example.rb")
    aliases = document.declarations.select(&:alias_target)

    assert_empty document.diagnostics
    assert_equal ["fetch", "load"], aliases.map(&:name)
    assert_equal ["read", "read"], aliases.map(&:alias_target)
    assert_equal [[:private, ["path"]], [:private, ["path"]]], aliases.map { |declaration| [declaration.visibility, declaration.parameters] }
  end

  def test_collects_singleton_method_aliases
    source = "class Reader\n  class << self\n    def build = new\n    alias create build\n    alias_method \"make\", \"build\"\n  end\nend\n"
    aliases = Zard.parse(source, path: "example.rb").declarations.select(&:alias_target)

    assert_equal [:singleton_method, :singleton_method], aliases.map(&:kind)
    assert_equal ["build", "build"], aliases.map(&:alias_target)
  end

  def test_preserves_an_unresolved_alias_with_a_diagnostic
    source = "class Reader\n  alias fetch inherited_read\nend\n"
    document = Zard.parse(source, path: "example.rb")
    declaration = document.declarations.find(&:alias_target)

    assert_equal "inherited_read", declaration.alias_target
    assert_equal :public, declaration.visibility
    assert_equal ["alias.unresolved-target"], document.diagnostics.map(&:code)
  end

  def test_preserves_the_class_superclass_expression_and_span
    source = "# Reads values.\nclass Demo::Reader < ::Base\nend\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal :class, declaration.kind
    assert_equal "::Base", declaration.superclass
    assert_equal "::Base", source.byteslice(declaration.superclass_span.start_offset...declaration.superclass_span.end_offset)
    assert_equal 2, declaration.superclass_span.start_line
  end

  def test_preserves_a_dynamic_superclass_expression_without_resolving_it
    source = "class Reader < superclass_for(:reader)\nend\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal "superclass_for(:reader)", declaration.superclass
  end

  def test_preserves_mixin_references_and_spans_without_resolving_them
    source = "class Reader\n  include Enumerable, Namespace::Readable\n  prepend instrumentation_for(:reader)\n  extend FactoryMethods\nend\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_equal %i[include include prepend extend], declaration.mixins.map(&:kind)
    assert_equal ["Enumerable", "Namespace::Readable", "instrumentation_for(:reader)", "FactoryMethods"], declaration.mixins.map(&:target)
    declaration.mixins.each do |mixin|
      assert_equal mixin.target, source.byteslice(mixin.span.start_offset...mixin.span.end_offset)
    end
  end

  def test_attaches_mixin_references_to_the_lexical_container_only
    source = "module Outer\n  include OuterFeature\n  class Reader\n    prepend ReaderFeature\n  end\n  extend OuterMethods\nend\n"
    outer, reader = Zard.parse(source, path: "example.rb").declarations

    assert_equal [[:include, "OuterFeature"], [:extend, "OuterMethods"]], outer.mixins.map { |mixin| [mixin.kind, mixin.target] }
    assert_equal [[:prepend, "ReaderFeature"]], reader.mixins.map { |mixin| [mixin.kind, mixin.target] }
  end

  def test_ignores_received_and_singleton_class_mixin_calls
    source = "class Reader\n  helper.include Feature\n  class << self\n    include SingletonFeature\n  end\nend\n"
    declaration = Zard.parse(source, path: "example.rb").declarations.fetch(0)

    assert_empty declaration.mixins
  end

  def test_applies_private_and_public_constant_visibility
    source = "module Demo\n  VALUE = 1\n  class Internal\n  end\n  private_constant :VALUE, :Internal\n  public_constant \"VALUE\"\nend\n"
    declarations = Zard.parse(source, path: "example.rb").declarations

    value = declarations.find { |declaration| declaration.kind == :constant }
    internal = declarations.find { |declaration| declaration.kind == :class }
    assert_equal :public, value.visibility
    assert_equal :private, internal.visibility
  end

  def test_applies_constant_visibility_to_every_reopened_declaration
    source = "module Demo\n  class Shared\n  end\n  class Shared\n  end\n  private_constant :Shared\nend\n"
    declarations = Zard.parse(source, path: "example.rb").declarations
      .select { |declaration| declaration.kind == :class }

    assert_equal [:private, :private], declarations.map(&:visibility)
  end

  def test_does_not_treat_calls_inside_method_bodies_as_declaration_dsl
    source = "class Reader\n  def configure\n    private\n    attr_reader :ghost\n    alias_method :copy, :source\n    private_constant :Ghost\n    include GhostFeature\n  end\n  def visible = nil\nend\n"
    document = Zard.parse(source, path: "example.rb")
    methods = document.declarations.select { |declaration| declaration.kind == :instance_method }
    attributes = document.declarations.select { |declaration| declaration.kind.to_s.include?("attribute") }
    reader = document.declarations.find { |declaration| declaration.kind == :class }

    assert_equal ["configure", "visible"], methods.map(&:name)
    assert_equal [:public, :public], methods.map(&:visibility)
    assert_empty attributes
    assert_empty reader.mixins
    assert_empty document.diagnostics
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
