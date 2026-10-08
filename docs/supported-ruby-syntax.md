# Supported Ruby Semantics

The ZARD parser models modern Ruby declarations statically without executing code. Runtime ancestry, dynamic metaprogramming, and foreign object evaluations are intentionally left unresolved.

### Visibility & Modifiers

- Declarations record `public`, `protected`, or `private` visibility. Markdown output includes public declarations only.
- Bare visibility calls, inline forms (`private def`, `private attr_reader`), named method modifiers (`private :read`), and `private_class_method` / `public_class_method` are supported.
- Visibility calls received by `self` belong to the current scope (method scope for instance visibility, singleton method scope for class methods).
- `module_function` records its private instance method and public singleton copy as separate declarations with shared provenance. Bare, named, inline, and splatted forms (`module_function(*attr_accessor(:name))`) are supported.
- `module_function` received by `self` belongs to the current module, like its bare form. Named `module_function` calls may target generated attribute methods, preserving the other accessor side with its original visibility.

### Attributes, Aliases & Method Removal

- Ruby `attr` declarations default to readers; the legacy `attr :name, true` form is preserved as an accessor. Attributes received by `self` belong to the current owner.
- Named attribute visibility modifiers are diagnosed because one attribute declaration may generate two methods; use lexical or inline visibility instead.
- Method aliases preserve their target name and inherit visibility and parameters when declared in the same source scope. Generated attribute readers and writers are valid alias targets (writer aliases use the conventional `value` parameter).
- Inline visibility and `module_function` modifiers around `alias_method` apply to the resulting alias. `alias_method` received by `self` belongs to the current method scope.
- Alias documentation remains separate from target documentation.
- `undef`, `undef_method`, and `remove_method` remove declarations from the current method scope. Removing or replacing one side of an attribute accessor preserves the other side.
- Later method, alias, and attribute definitions replace earlier declarations of the same name in the same source scope.

### Dynamic Definitions & Evaluation Blocks

- Literal `define_method` and `define_singleton_method` calls produce method declarations with preserved block parameters, visibility, receiver, refinement scope, and documentation provenance.
- `define_method` received by `self` belongs to the current method scope.
- Inline `private define_method`, `module_function define_method`, and class-method visibility modifiers around `define_singleton_method` preserve the visibility produced by Ruby.
- Declarations in bare or `self` evaluation blocks remain in the current owner. Blocks evaluated by another receiver are not attributed to the lexical owner.
- In bare or `self.instance_eval` blocks, bare `def` becomes a singleton method, while method-definition calls, attributes, and constants retain their lexical owner. Foreign instance-evaluation blocks are not resolved.

### Classes, Modules & Container Builders

- Class declarations preserve explicit superclass expressions and source spans without resolving runtime ancestry.
- Assignments from `Data.define`, `Struct.new`, and `Class.new` produce class declarations; assignments from `Module.new` produce module declarations. Container builders preserve generated attributes and block members within the container scope.
- Literal Symbol and String member names produce generated attributes; the leading String class name accepted by `Struct.new` is not a member.
- Named subclasses (e.g. `class Point < Data.define(:x)`) preserve generated attributes while retaining the explicit superclass expression.
- `Class.new(Struct.new(...))` and `Class.new(Data.define(...))` chains preserve inherited generated attributes when no intermediate factory block can override them.
- Standard library `DelegateClass(Target)` calls are treated as class builders and preserve the delegated target expression as source provenance.
- Conditional container builders (`||=`, `Registry = Registry || Module.new`) and transparent `.freeze` tails (including repeated or block forms) are supported.

### Mixins, Singletons & Refinements

- `include`, `prepend`, and `extend` targets are preserved with source spans and listed in documented containers without resolving inheritance trees. Mixin calls received by `self` belong to the current container.
- Singleton methods and attributes preserve explicit receiver expressions (or `class <<` expressions).
- Ruby `refine` blocks and their members remain scoped to the refinement target and separate from ordinary module members. `refine` received by `self` belongs to the current module.

### Constants & Namespaces

- `private_constant` and `public_constant` update constant visibility in the same namespace. Constant visibility calls received by `self` belong to the current namespace.
- Bare or `self.autoload` calls with literal Symbol or String names produce constant declarations for the current ordinary owner without guessing the loaded value's kind.
- Bare or `self.const_set` calls with literal names produce declarations in the current ordinary class or module body; container-builder values retain their generated scope.
- `remove_const` removes matching declarations and their nested APIs from the current namespace. Unconditional assignments and literal `const_set` replace earlier declarations, while conditional initialization (`||=`) is non-destructive.

See the [usage guide](usage.md) for installation, model access, and CLI behavior.

