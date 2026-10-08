# ZARD

ZARD is an AI-friendly Ruby self-documentation notation built around RBS and Rigor extensions. It keeps human-facing API documentation separate from checked type contracts.

The package is under active design. The first vertical slice parses Ruby source into a versioned ZARD model and renders its API documentation as Markdown.

## Syntax direction

Plain RBS remains visible to the wider Ruby type ecosystem. Rigor-only refinements use `@extrbs`, while prose uses ZARD documentation tags.

```ruby
# @extrbs return: non-empty-string
# @rbs path: String
# @rbs return: String
# @param path — Path to the name file.
# @return The stored name.
def read_name(path)
  File.read(path).strip
end
```

See [CONTEXT.md](CONTEXT.md) and [docs/adr](docs/adr) for the current language and architecture decisions.

## Usage

The core gem parses Ruby source without interpreting `@extrbs` type payloads:

```ruby
document = Zard.parse(source, path: "lib/example.rb")
```

The separate `zard-doc` gem renders the API documentation in that model:

```ruby
require "zard/doc"

markdown = Zard::Doc.render(document)
```

The initial renderer supports class, module, constant, attribute, and method prose plus `@param`, `@return`, `@yieldparam`, `@yieldreturn`, `@option`, `@raise`, `@note`, `@see`, `@deprecated`, and `@example`. Contracts remain available in the model and are not copied into API prose.

Lint source files or directories with `zard-doc lint`. Warnings are reported without failing by default; use `--fail-on warning` to make them fail in CI.

Render Markdown to standard output with `zard-doc render lib`.
Use `-` as the input path to lint or render Ruby source from standard input.

ZARD documentation requires UTF-8 source text. Non-UTF-8 Ruby source may still carry `@rbs`, `#:`, and `@extrbs` contracts.

InlineRBS trailing prose after `--` is stored as a contract note. It is not copied into API documentation.

Documentation descriptions continue across plain comment lines until the next annotation or contract. No continuation marker is required.

Declarations record `public`, `protected`, or `private` visibility. Markdown output includes public declarations only. Bare visibility calls, inline forms such as `private def` and `private attr_reader`, named method modifiers such as `private :read`, and `private_class_method` / `public_class_method` are supported. Named attribute modifiers are diagnosed because one attribute declaration may represent two generated methods; use lexical or inline visibility for attributes.
Instance visibility calls received by `self` belong to the current method scope, like their bare forms.
Class method visibility calls received by `self` belong to the current singleton method scope, like their bare forms.
Ruby's `attr` declarations are readers by default. The legacy `attr :name, true` form is preserved as an accessor.
Attribute declarations received by `self` belong to the current owner, like their bare forms.

`module_function` records its private instance method and public singleton copy as separate declarations with shared source provenance. Bare, named, and inline forms are supported.
`module_function` received by `self` belongs to the current module, like its bare form.

Method aliases preserve their target name and inherit visibility and parameters when the target is declared in the same source scope. Alias documentation remains separate from target documentation.
Inline visibility and `module_function` modifiers around `alias_method` apply to the resulting alias.
`alias_method` received by `self` belongs to the current method scope, like its bare form.
`undef`, `undef_method`, and `remove_method` remove declarations from the current method scope. Removing one side of an attribute accessor preserves the other side.

Literal `define_method` and `define_singleton_method` calls produce method declarations. Their block parameters, visibility, receiver, refinement scope, and documentation provenance are preserved.
`define_method` received by `self` belongs to the current method scope, like its bare form.
Inline `private define_method`, `module_function define_method`, and class-method visibility modifiers around `define_singleton_method` preserve the visibility produced by Ruby.
Declarations in bare or `self` evaluation blocks remain in the current owner. Blocks evaluated by another receiver are not attributed to the lexical owner.
In bare or `self.instance_eval` blocks, a bare `def` is a singleton method while method-definition calls, attributes, and constants retain their lexical owner. Foreign instance-evaluation blocks are not resolved.

Class declarations preserve the explicit superclass expression and its source span without resolving ancestry.

Classes assigned from `Data.define` and `Struct.new` preserve the builder call, generated attributes, and block members as one class scope.
Literal Symbol and String member names produce generated attributes; the leading String class name accepted by `Struct.new` is not a member.
Named subclasses such as `class Point < Data.define(:x)` also preserve the generated attributes while retaining the explicit superclass expression.
`Class.new` assignments are also class builders, so their optional superclass, mixins, constants, and block members stay inside the generated class scope.
`Module.new` assignments are module builders, so their mixins, constants, and block members stay inside the generated module scope.
Container builders used with `||=` are treated as conditional class or module initialization. Other constant reassignments remain outside the declaration model.
Assignments from the standard library's `DelegateClass(Target)` are class builders and preserve the delegated target expression as source provenance.
Argumentless `.freeze` tails are transparent for container builders, including block-form and repeated tails.
Self-referential guards such as `Registry = Registry || Module.new` are treated like the equivalent `||=` initialization.
`Class.new(Struct.new(...))` and `Class.new(Data.define(...))` chains preserve inherited generated attributes when no intermediate factory block can override them.

Class and module declarations preserve explicit `include`, `prepend`, and `extend` targets with source spans without resolving ancestry. Documented containers list these mixin references in Markdown.
Mixin calls received by `self` belong to the current container, like their bare forms.

Singleton methods and attributes preserve an explicit receiver or `class <<` expression with source provenance. Documentation renders that source receiver without resolving its runtime object.

Ruby refinements and their members remain separate from ordinary members of the enclosing module. The refinement target is preserved as a source expression with its span.
`refine` received by `self` belongs to the current module, like its bare form.

`private_constant` and `public_constant` update the visibility of class, module, and constant declarations in the same namespace.
Constant visibility calls received by `self` belong to the current namespace, like their bare forms.
Bare or `self.autoload` calls with literal Symbol or String names produce constant declarations for the current ordinary owner without guessing the loaded value's class or module kind.
Bare or `self.const_set` calls with literal names produce declarations in the current ordinary class or module body; container-builder values retain their generated scope.

## Installation

Until the first RubyGems release, add the repository to your Gemfile:

```ruby
gem "zard", github: "rigortype/zard"
gem "zard-doc", github: "rigortype/zard"
```

## Development

Run the setup script and the default verification task:

```sh
bin/setup
bundle exec rake
```

The default task runs tests, Standard, RBS validation, and a gem build.

## License

ZARD is available under the Mozilla Public License 2.0. See [LICENSE](LICENSE).
