# frozen_string_literal: true

require "prism"

module Zard
  module Parsing
    class Parser
      def self.call(source, path:)
        new(source, path).call
      end

      def initialize(source, path)
        @source = source
        @path = path
      end

      def call
        result = Prism.parse(@source)
        diagnostics = result.errors.map do |error|
          diagnostic("ruby.syntax", :error, error.message, span(error.location))
        end

        declarations = DeclarationCollector.new(
          @source,
          @path,
          result.comments,
          diagnostics,
          result.encoding,
          result.source
        ).call(result.value)

        Model::V1::Document.new(
          path: @path,
          declarations: declarations.freeze,
          diagnostics: diagnostics.freeze
        )
      end

      private

      def diagnostic(code, severity, message, location)
        Model::V1::Diagnostic.new(code: code, severity: severity, message: message, span: location)
      end

      def span(location)
        Model::V1::SourceSpan.new(
          path: @path,
          start_line: location.start_line,
          start_column: location.start_column,
          end_line: location.end_line,
          end_column: location.end_column,
          start_offset: location.start_offset,
          end_offset: location.end_offset
        )
      end
    end

    class DeclarationCollector < Prism::Visitor
      ATTRIBUTE_KINDS = {
        attr_reader: :attribute_reader,
        attr_writer: :attribute_writer,
        attr_accessor: :attribute_accessor
      }.freeze
      VISIBILITY_NAMES = %i[public protected private].freeze
      CLASS_METHOD_VISIBILITY = {
        private_class_method: :private,
        public_class_method: :public
      }.freeze
      CONSTANT_VISIBILITY = {
        private_constant: :private,
        public_constant: :public
      }.freeze
      MIXIN_NAMES = %i[include prepend extend].freeze
      METHOD_DEFINITION_NAMES = %i[define_method define_singleton_method].freeze
      CONTAINER_BUILDERS = {
        ["Data", :define] => {kind: :class, attribute_kind: :attribute_reader}.freeze,
        ["Struct", :new] => {kind: :class, attribute_kind: :attribute_accessor}.freeze,
        ["Class", :new] => {kind: :class, attribute_kind: nil}.freeze,
        ["Module", :new] => {kind: :module, attribute_kind: nil}.freeze,
        [nil, :DelegateClass] => {kind: :class, attribute_kind: nil}.freeze
      }.freeze

      def initialize(source, path, comments, diagnostics, encoding, prism_source)
        @source = source
        @path = path
        @comments = comments.select { |comment| standalone?(comment) && !magic_comment?(comment) }
        @diagnostics = diagnostics
        @encoding = encoding
        @prism_source = prism_source
        @declarations = []
        @namespace = []
        @singleton_depth = 0
        @singleton_receiver = nil
        @singleton_receiver_span = nil
        @refinement = nil
        @refinement_span = nil
        @instance_visibility = :public
        @singleton_visibility = :public
        @container_kind = nil
        @module_function_mode = false
        @method_depth = 0
        @container_declaration_index = nil
      end

      def call(program)
        program.accept(self)
        @declarations.freeze
      end

      def visit_module_node(node)
        declaration_index = collect_path_declaration(:module, node.constant_path.location.slice, node)
        within_namespace(node.constant_path.location.slice, :module, declaration_index) { node.body&.accept(self) }
      end

      def visit_class_node(node)
        builder_call = node.superclass if class_builder?(node.superclass)
        declaration_index = collect_path_declaration(
          :class,
          node.constant_path.location.slice,
          node,
          superclass: node.superclass&.location&.slice,
          superclass_span: node.superclass ? span(node.superclass.location) : nil
        )
        within_namespace(node.constant_path.location.slice, :class, declaration_index) do
          collect_container_builder_attributes(builder_call) if builder_call
          node.body&.accept(self)
        end
      end

      def visit_constant_write_node(node)
        call = container_builder_call(node.value)
        return visit_container_builder_write(node.name.to_s, node, call) if call

        collect_path_declaration(:constant, node.name.to_s, node)
        super
      end

      def visit_constant_path_write_node(node)
        call = container_builder_call(node.value)
        return visit_container_builder_write(node.target.location.slice, node, call) if call

        collect_path_declaration(:constant, node.target.location.slice, node)
        super
      end

      def visit_constant_or_write_node(node)
        call = container_builder_call(node.value)
        return visit_container_builder_write(node.name.to_s, node, call) if call

        super
      end

      def visit_constant_path_or_write_node(node)
        call = container_builder_call(node.value)
        return visit_container_builder_write(node.target.location.slice, node, call) if call

        super
      end

      def visit_singleton_class_node(node)
        previous_visibility = @singleton_visibility
        previous_receiver = @singleton_receiver
        previous_receiver_span = @singleton_receiver_span
        @singleton_visibility = :public
        @singleton_receiver = node.expression.location.slice
        @singleton_receiver_span = span(node.expression.location)
        @singleton_depth += 1
        node.body&.accept(self)
      ensure
        @singleton_depth -= 1
        @singleton_visibility = previous_visibility
        @singleton_receiver = previous_receiver
        @singleton_receiver_span = previous_receiver_span
      end

      def visit_def_node(node)
        collect_method_declarations(node)

        within_method_body { node.body&.accept(self) }
      end

      def visit_alias_method_node(node)
        collect_method_alias(node.new_name.unescaped, node.old_name.unescaped, node)
      end

      def visit_call_node(node)
        return super if @method_depth.positive?

        return visit_refinement_call(node) if refinement_call?(node)
        return visit_method_definition_call(node) if method_definition_call?(node)

        collect_mixin_references(node) if mixin_call?(node)

        if node.name == :module_function && node.receiver.nil? && module_function_context?
          return visit_module_function_call(node) { super }
        end

        if node.receiver.nil? && (class_visibility = CLASS_METHOD_VISIBILITY[node.name])
          return visit_class_method_visibility_call(node, class_visibility) { super }
        end

        if node.receiver.nil? && (constant_visibility = CONSTANT_VISIBILITY[node.name])
          return visit_constant_visibility_call(node, constant_visibility) { super }
        end

        visibility = VISIBILITY_NAMES.find { |name| node.name == name && node.receiver.nil? }
        return visit_visibility_call(node, visibility) { super } if visibility

        if node.name == :alias_method && node.receiver.nil?
          collect_alias_method_call(node)
          return super
        end

        collect_attribute_declarations(node)
        super
      end

      private

      def class_builder?(node)
        descriptor = container_builder_descriptor(node)
        descriptor && descriptor.fetch(:kind) == :class
      end

      def container_builder_descriptor(node)
        call = container_builder_call(node)
        return unless call

        CONTAINER_BUILDERS[container_builder_key(call)]
      end

      def visit_container_builder_write(path, node, call)
        descriptor = CONTAINER_BUILDERS.fetch(container_builder_key(call))
        builder, builder_span = container_builder_reference(call)
        declaration_index = collect_path_declaration(
          descriptor.fetch(:kind),
          path,
          node,
          container_builder: builder,
          container_builder_span: builder_span
        )
        within_namespace(path, descriptor.fetch(:kind), declaration_index) do
          collect_container_builder_attributes(call)
          call.block&.body&.accept(self)
        end
      end

      def container_builder_reference(call)
        return [call.location.slice, span(call.location)] unless call.block

        length = call.block.location.start_offset - call.location.start_offset
        source = @source.byteslice(call.location.start_offset, length).rstrip
        location = Prism::Location.new(@prism_source, call.location.start_offset, source.bytesize)
        [source, span(location)]
      end

      def collect_container_builder_attributes(call)
        descriptor = CONTAINER_BUILDERS.fetch(container_builder_key(call))
        attribute_kind = descriptor.fetch(:attribute_kind)
        return unless attribute_kind

        arguments = call.arguments&.arguments || []
        arguments.grep(Prism::SymbolNode).each do |argument|
          append_declaration(
            kind: :"instance_#{attribute_kind}",
            name: argument.unescaped,
            namespace: current_namespace,
            visibility: :public,
            parameters: [].freeze,
            node: argument,
            comments: [].freeze,
            parsed: {documentation: [].freeze, contracts: [].freeze}
          )
        end
      end

      def container_builder_key(node)
        return unless node.is_a?(Prism::CallNode)

        receiver = node.receiver&.location&.slice&.sub(/\A::/, "")
        [receiver, node.name]
      end

      def container_builder_call(node)
        node = node.receiver while freeze_tail?(node)
        return unless node.is_a?(Prism::CallNode)

        node if CONTAINER_BUILDERS.key?(container_builder_key(node))
      end

      def freeze_tail?(node)
        node.is_a?(Prism::CallNode) && node.name == :freeze && !node.safe_navigation? &&
          node.receiver && node.arguments.nil? && node.block.nil?
      end

      def method_definition_call?(node)
        return false unless METHOD_DEFINITION_NAMES.include?(node.name)
        return true if node.name == :define_singleton_method

        node.receiver.nil? && (!@namespace.empty? || @refinement)
      end

      def visit_method_definition_call(node)
        arguments = node.arguments&.arguments || []
        name = attribute_name(arguments.first) if arguments.first
        collect_call_method_declaration(node, name) if name
        within_method_body { node.block&.body&.accept(self) }
      end

      def collect_call_method_declaration(node, name)
        parameters = parameter_names(node.block&.parameters&.parameters).freeze
        singleton = node.name == :define_singleton_method
        kind = singleton ? :singleton_method : current_method_kind
        receiver = if singleton
          node.receiver&.location&.slice || "self"
        else
          current_singleton_receiver
        end
        receiver_span = if singleton
          span(node.receiver.location) if node.receiver
        else
          current_singleton_receiver_span
        end
        visibility = singleton ? @singleton_visibility : current_visibility
        collect_method_entries(
          kind: kind,
          name: name,
          namespace: current_namespace,
          visibility: visibility,
          parameters: parameters,
          receiver: receiver,
          receiver_span: receiver_span,
          node: node
        )
      end

      def refinement_call?(node)
        node.name == :refine &&
          node.receiver.nil? &&
          node.block &&
          @container_kind == :module &&
          @singleton_depth.zero? &&
          node.arguments&.arguments&.length == 1
      end

      def visit_refinement_call(node)
        target_node = node.arguments.arguments.fetch(0)
        target = target_node.location.slice
        collect_declaration(
          kind: :refinement,
          name: target,
          namespace: current_namespace,
          visibility: :public,
          parameters: [].freeze,
          node: node
        )
        within_refinement(target, span(target_node.location)) do
          node.block.body&.accept(self)
        end
      end

      def mixin_call?(node)
        MIXIN_NAMES.include?(node.name) &&
          node.receiver.nil? &&
          %i[class module].include?(@container_kind) &&
          @container_declaration_index &&
          @singleton_depth.zero?
      end

      def collect_mixin_references(node)
        arguments = node.arguments&.arguments || []
        return if arguments.empty?

        declaration = @declarations.fetch(@container_declaration_index)
        mixins = arguments.map do |argument|
          Model::V1::MixinReference.new(
            kind: node.name,
            target: argument.location.slice,
            span: span(argument.location)
          )
        end
        @declarations[@container_declaration_index] = declaration_with_mixins(declaration, declaration.mixins + mixins)
      end

      def within_method_body
        @method_depth += 1
        yield
      ensure
        @method_depth -= 1
      end

      def collect_alias_method_call(node)
        arguments = node.arguments&.arguments || []
        return unless arguments.length == 2

        new_name, old_name = arguments.map { |argument| attribute_name(argument) }
        collect_method_alias(new_name, old_name, node) if new_name && old_name
      end

      def collect_method_alias(name, target, node)
        kind = current_method_kind
        original = @declarations.reverse_each.find do |declaration|
          declaration.kind == kind &&
            declaration.namespace == current_namespace &&
            declaration_scope_matches?(declaration, current_singleton_receiver) &&
            declaration.name == target
        end
        unless original
          @diagnostics << Model::V1::Diagnostic.new(
            code: "alias.unresolved-target",
            severity: :warning,
            message: "The alias target is not declared in this source scope.",
            span: span(node.location)
          )
        end

        comments, parsed = parse_comments(node)
        append_declaration(
          kind: kind,
          name: name,
          namespace: current_namespace,
          visibility: original&.visibility || current_visibility,
          parameters: original&.parameters || [].freeze,
          receiver: current_singleton_receiver,
          receiver_span: current_singleton_receiver_span,
          refinement: @refinement,
          refinement_span: @refinement_span,
          alias_target: target,
          node: node,
          comments: comments,
          parsed: parsed
        )
      end

      def collect_method_declarations(node)
        kind = singleton_method?(node) ? :singleton_method : :instance_method
        name = node.name.to_s
        namespace = current_namespace
        parameters = parameter_names(node.parameters).freeze
        receiver = node.receiver&.location&.slice || current_singleton_receiver
        receiver_span = node.receiver ? span(node.receiver.location) : current_singleton_receiver_span
        collect_method_entries(
          kind: kind,
          name: name,
          namespace: namespace,
          visibility: method_visibility(node),
          parameters: parameters,
          receiver: receiver,
          receiver_span: receiver_span,
          node: node
        )
      end

      def collect_method_entries(kind:, name:, namespace:, visibility:, parameters:, receiver:, receiver_span:, node:)
        unless kind == :instance_method && module_function_definition?(node)
          return collect_declaration(
            kind: kind,
            name: name,
            namespace: namespace,
            visibility: visibility,
            parameters: parameters,
            receiver: receiver,
            receiver_span: receiver_span,
            refinement: @refinement,
            refinement_span: @refinement_span,
            node: node
          )
        end

        comments, parsed = parse_comments(node)
        append_declaration(
          kind: :instance_method,
          name: name,
          namespace: namespace,
          visibility: :private,
          parameters: parameters,
          receiver: receiver,
          receiver_span: receiver_span,
          refinement: @refinement,
          refinement_span: @refinement_span,
          node: node,
          comments: comments,
          parsed: parsed
        )
        append_declaration(
          kind: :singleton_method,
          name: name,
          namespace: namespace,
          visibility: :public,
          parameters: parameters,
          receiver: receiver,
          receiver_span: receiver_span,
          refinement: @refinement,
          refinement_span: @refinement_span,
          node: node,
          comments: comments,
          parsed: parsed
        )
      end

      def collect_attribute_declarations(node)
        attribute_kind = ATTRIBUTE_KINDS[node.name]
        return unless attribute_kind && node.receiver.nil? && !@namespace.empty?

        names = node.arguments&.arguments&.filter_map { |argument| attribute_name(argument) } || []
        return if names.empty?

        comments, parsed = parse_comments(node)
        scope = @singleton_depth.positive? ? :singleton : :instance
        kind = :"#{scope}_#{attribute_kind}"
        names.each do |name|
          append_declaration(
            kind: kind,
            name: name,
            namespace: @namespace.join("::"),
            visibility: current_visibility,
            parameters: [].freeze,
            receiver: current_singleton_receiver,
            receiver_span: current_singleton_receiver_span,
            refinement: @refinement,
            refinement_span: @refinement_span,
            node: node,
            comments: comments,
            parsed: parsed
          )
        end
      end

      def attribute_name(argument)
        argument.unescaped if argument.is_a?(Prism::SymbolNode) || argument.is_a?(Prism::StringNode)
      end

      def collect_path_declaration(kind, path, node, superclass: nil, superclass_span: nil, container_builder: nil, container_builder_span: nil)
        parts = namespace_parts(path)
        collect_declaration(
          kind: kind,
          name: parts.last,
          namespace: (parts.length > 1) ? parts[0...-1].join("::") : nil,
          visibility: :public,
          parameters: [].freeze,
          superclass: superclass,
          superclass_span: superclass_span,
          container_builder: container_builder,
          container_builder_span: container_builder_span,
          node: node
        )
      end

      def collect_declaration(kind:, name:, namespace:, visibility:, parameters:, node:, receiver: nil, receiver_span: nil, refinement: nil, refinement_span: nil, superclass: nil, superclass_span: nil, container_builder: nil, container_builder_span: nil)
        comments, parsed = parse_comments(node)
        append_declaration(
          kind: kind,
          name: name,
          namespace: namespace,
          visibility: visibility,
          parameters: parameters,
          receiver: receiver,
          receiver_span: receiver_span,
          refinement: refinement,
          refinement_span: refinement_span,
          superclass: superclass,
          superclass_span: superclass_span,
          container_builder: container_builder,
          container_builder_span: container_builder_span,
          node: node,
          comments: comments,
          parsed: parsed
        )
      end

      def append_declaration(kind:, name:, namespace:, visibility:, parameters:, node:, comments:, parsed:, receiver: nil, receiver_span: nil, refinement: nil, refinement_span: nil, alias_target: nil, superclass: nil, superclass_span: nil, container_builder: nil, container_builder_span: nil)
        @declarations << Model::V1::Declaration.new(
          kind: kind,
          name: name,
          namespace: namespace,
          visibility: visibility,
          parameters: parameters,
          receiver: receiver,
          receiver_span: receiver_span,
          refinement: refinement,
          refinement_span: refinement_span,
          alias_target: alias_target,
          superclass: superclass,
          superclass_span: superclass_span,
          container_builder: container_builder,
          container_builder_span: container_builder_span,
          span: span(node.location),
          comment_span: comment_span(comments),
          documentation: parsed.fetch(:documentation).freeze,
          contracts: parsed.fetch(:contracts).freeze
        )
        @declarations.length - 1
      end

      def parse_comments(node)
        comments = comment_block_for(node.location.start_line)
        parsed = CommentBlockParser.new(@source, @path, comments, @diagnostics, @encoding).call
        [comments, parsed]
      end

      def within_namespace(name, kind, declaration_index)
        previous_namespace = @namespace
        previous_instance_visibility = @instance_visibility
        previous_singleton_visibility = @singleton_visibility
        previous_container_kind = @container_kind
        previous_module_function_mode = @module_function_mode
        previous_container_declaration_index = @container_declaration_index
        previous_refinement = @refinement
        previous_refinement_span = @refinement_span
        @namespace = namespace_parts(name)
        @instance_visibility = :public
        @singleton_visibility = :public
        @container_kind = kind
        @module_function_mode = false
        @container_declaration_index = declaration_index
        @refinement = nil
        @refinement_span = nil
        yield
      ensure
        @namespace = previous_namespace
        @instance_visibility = previous_instance_visibility
        @singleton_visibility = previous_singleton_visibility
        @container_kind = previous_container_kind
        @module_function_mode = previous_module_function_mode
        @container_declaration_index = previous_container_declaration_index
        @refinement = previous_refinement
        @refinement_span = previous_refinement_span
      end

      def within_refinement(target, target_span)
        previous_instance_visibility = @instance_visibility
        previous_singleton_visibility = @singleton_visibility
        previous_container_kind = @container_kind
        previous_module_function_mode = @module_function_mode
        previous_container_declaration_index = @container_declaration_index
        previous_refinement = @refinement
        previous_refinement_span = @refinement_span
        @instance_visibility = :public
        @singleton_visibility = :public
        @container_kind = :refinement
        @module_function_mode = false
        @container_declaration_index = nil
        @refinement = target
        @refinement_span = target_span
        yield
      ensure
        @instance_visibility = previous_instance_visibility
        @singleton_visibility = previous_singleton_visibility
        @container_kind = previous_container_kind
        @module_function_mode = previous_module_function_mode
        @container_declaration_index = previous_container_declaration_index
        @refinement = previous_refinement
        @refinement_span = previous_refinement_span
      end

      def namespace_parts(name)
        prefix = name.start_with?("::") ? [] : @namespace
        prefix + name.sub(/\A::/, "").split("::")
      end

      def singleton_method?(node)
        !node.receiver.nil? || @singleton_depth.positive?
      end

      def method_visibility(node)
        return :public if node.receiver && @singleton_depth.zero?

        current_visibility
      end

      def current_visibility
        @singleton_depth.positive? ? @singleton_visibility : @instance_visibility
      end

      def visit_visibility_call(node, visibility)
        arguments = node.arguments&.arguments
        if arguments.nil? || arguments.empty?
          @module_function_mode = false if module_function_context?
          set_current_visibility(visibility)
          return yield
        end

        if arguments.any? { |argument| visibility_declaration?(argument) }
          return with_visibility(visibility) { yield }
        end

        names = arguments.filter_map { |argument| attribute_name(argument) }
        unless names.empty?
          apply_named_visibility(
            names,
            visibility,
            node,
            method_kind: current_method_kind,
            attribute_scope: current_attribute_scope,
            receiver: current_singleton_receiver
          )
        end
        yield
      end

      def visit_module_function_call(node)
        arguments = node.arguments&.arguments
        if arguments.nil? || arguments.empty?
          @instance_visibility = :private
          @module_function_mode = true
          return yield
        end

        if arguments.any? { |argument| argument.is_a?(Prism::DefNode) }
          return with_module_function_mode { yield }
        end

        yield
        names = arguments.filter_map { |argument| attribute_name(argument) }
        names.each { |name| apply_named_module_function(name) }
      end

      def module_function_context?
        @container_kind == :module && @singleton_depth.zero?
      end

      def module_function_definition?(node)
        @module_function_mode && module_function_context? && node.receiver.nil?
      end

      def with_module_function_mode
        previous_visibility = @instance_visibility
        previous_mode = @module_function_mode
        @instance_visibility = :private
        @module_function_mode = true
        yield
      ensure
        @instance_visibility = previous_visibility
        @module_function_mode = previous_mode
      end

      def apply_named_module_function(name)
        index = @declarations.rindex do |declaration|
          declaration.kind == :instance_method &&
            declaration.namespace == current_namespace &&
            declaration.name == name
        end
        return unless index

        declaration = @declarations.fetch(index)
        @declarations[index] = declaration_with_visibility(declaration, :private)
        @declarations << declaration_with_kind_and_visibility(declaration, :singleton_method, :public)
      end

      def visit_class_method_visibility_call(node, visibility)
        arguments = node.arguments&.arguments || []
        yield
        names = arguments.filter_map do |argument|
          if argument.is_a?(Prism::DefNode) && argument.receiver
            argument.name.to_s
          else
            attribute_name(argument)
          end
        end
        unless names.empty?
          apply_named_visibility(
            names,
            visibility,
            node,
            method_kind: :singleton_method,
            attribute_scope: "singleton_attribute_",
            receiver: nil
          )
        end
      end

      def visit_constant_visibility_call(node, visibility)
        arguments = node.arguments&.arguments || []
        yield
        names = arguments.filter_map { |argument| attribute_name(argument) }
        return if names.empty?

        @declarations.map! do |declaration|
          if %i[class module constant].include?(declaration.kind) &&
              declaration.namespace == current_namespace &&
              names.include?(declaration.name)
            declaration_with_visibility(declaration, visibility)
          else
            declaration
          end
        end
      end

      def visibility_declaration?(node)
        node.is_a?(Prism::DefNode) || (node.is_a?(Prism::CallNode) && ATTRIBUTE_KINDS.key?(node.name))
      end

      def set_current_visibility(visibility)
        if @singleton_depth.positive?
          @singleton_visibility = visibility
        else
          @instance_visibility = visibility
        end
      end

      def with_visibility(visibility)
        previous_visibility = current_visibility
        set_current_visibility(visibility)
        yield
      ensure
        set_current_visibility(previous_visibility)
      end

      def apply_named_visibility(names, visibility, node, method_kind:, attribute_scope:, receiver:)
        attribute_match = false
        @declarations.map! do |declaration|
          next declaration unless declaration.namespace == current_namespace
          next declaration unless declaration_scope_matches?(declaration, receiver)

          if declaration.kind == method_kind && names.include?(declaration.name)
            declaration_with_visibility(declaration, visibility)
          elsif attribute_in_scope?(declaration, attribute_scope) && (attribute_method_names(declaration) & names).any?
            attribute_match = true
            (visibility == :public) ? declaration : declaration_with_visibility(declaration, visibility)
          else
            declaration
          end
        end

        return unless attribute_match

        @diagnostics << Model::V1::Diagnostic.new(
          code: "visibility.named-attribute",
          severity: :warning,
          message: "Use a lexical or inline visibility modifier for an attribute declaration.",
          span: span(node.location)
        )
      end

      def declaration_scope_matches?(declaration, receiver)
        receiver_matches = if receiver.nil? || receiver == "self"
          declaration.receiver.nil? || declaration.receiver == "self"
        else
          declaration.receiver == receiver
        end
        receiver_matches && declaration.refinement == @refinement
      end

      def current_namespace
        @namespace.empty? ? nil : @namespace.join("::")
      end

      def current_method_kind
        @singleton_depth.positive? ? :singleton_method : :instance_method
      end

      def current_singleton_receiver
        @singleton_receiver if @singleton_depth.positive?
      end

      def current_singleton_receiver_span
        @singleton_receiver_span if @singleton_depth.positive?
      end

      def current_attribute_scope
        @singleton_depth.positive? ? "singleton_attribute_" : "instance_attribute_"
      end

      def attribute_in_scope?(declaration, scope)
        declaration.kind.to_s.start_with?(scope)
      end

      def attribute_method_names(declaration)
        case declaration.kind.to_s
        when /_attribute_reader\z/
          [declaration.name]
        when /_attribute_writer\z/
          ["#{declaration.name}="]
        else
          [declaration.name, "#{declaration.name}="]
        end
      end

      def declaration_with_visibility(declaration, visibility)
        declaration_with_kind_and_visibility(declaration, declaration.kind, visibility)
      end

      def declaration_with_mixins(declaration, mixins)
        declaration_with_kind_and_visibility(declaration, declaration.kind, declaration.visibility, mixins: mixins.freeze)
      end

      def declaration_with_kind_and_visibility(declaration, kind, visibility, mixins: declaration.mixins)
        Model::V1::Declaration.new(
          kind: kind,
          name: declaration.name,
          namespace: declaration.namespace,
          visibility: visibility,
          parameters: declaration.parameters,
          receiver: declaration.receiver,
          receiver_span: declaration.receiver_span,
          refinement: declaration.refinement,
          refinement_span: declaration.refinement_span,
          alias_target: declaration.alias_target,
          superclass: declaration.superclass,
          superclass_span: declaration.superclass_span,
          container_builder: declaration.container_builder,
          container_builder_span: declaration.container_builder_span,
          mixins: mixins,
          span: declaration.span,
          comment_span: declaration.comment_span,
          documentation: declaration.documentation,
          contracts: declaration.contracts
        )
      end

      def parameter_names(parameters)
        return [] unless parameters

        names = []
        names.concat(parameters.requireds.map { |parameter| parameter_name(parameter) })
        names.concat(parameters.optionals.map { |parameter| parameter_name(parameter) })
        names << prefixed_name("*", parameters.rest) if parameters.rest
        names.concat(parameters.posts.map { |parameter| parameter_name(parameter) })
        names.concat(parameters.keywords.map { |parameter| "#{parameter.name}:" })
        names << prefixed_name("**", parameters.keyword_rest) if parameters.keyword_rest
        names << prefixed_name("&", parameters.block) if parameters.block
        names
      end

      def parameter_name(parameter)
        return parameter.location.slice unless parameter.respond_to?(:name)

        parameter.name.to_s
      end

      def prefixed_name(prefix, parameter)
        return parameter.location.slice unless parameter.respond_to?(:name)

        parameter.name ? "#{prefix}#{parameter.name}" : prefix
      end

      def standalone?(comment)
        offset = comment.location.start_offset
        line_start = offset.zero? ? 0 : (@source.b.rindex("\n", offset - 1) || -1) + 1
        prefix = @source.byteslice(line_start, offset - line_start)
        prefix.match?(/\A[\t ]*\z/)
      end

      def magic_comment?(comment)
        return false if comment.location.start_line > 2

        comment.location.slice.match?(/\A#\s*(?:en)?coding\s*[:=]|\A#\s*frozen_string_literal\s*:/i)
      end

      def comment_block_for(declaration_line)
        expected_line = declaration_line - 1
        block = []

        @comments.reverse_each do |comment|
          next if comment.location.end_line > expected_line
          break if comment.location.end_line < expected_line

          block << comment
          expected_line = comment.location.start_line - 1
        end

        block.reverse
      end

      def comment_span(comments)
        return nil if comments.empty?

        first = comments.first.location
        last = comments.last.location
        Model::V1::SourceSpan.new(
          path: @path,
          start_line: first.start_line,
          start_column: first.start_column,
          end_line: last.end_line,
          end_column: last.end_column,
          start_offset: first.start_offset,
          end_offset: last.end_offset
        )
      end

      def span(location)
        Model::V1::SourceSpan.new(
          path: @path,
          start_line: location.start_line,
          start_column: location.start_column,
          end_line: location.end_line,
          end_column: location.end_column,
          start_offset: location.start_offset,
          end_offset: location.end_offset
        )
      end
    end

    class CommentBlockParser
      def initialize(source, path, comments, diagnostics, encoding)
        @source = source
        @path = path
        @comments = comments
        @diagnostics = diagnostics
        @encoding = encoding
      end

      def call
        documentation = []
        contracts = []
        seen_non_extrbs_annotation = false
        pending = nil

        @comments.each do |comment|
          raw = comment.location.slice
          body = comment_body(raw)

          if annotation_boundary?(body, raw)
            flush_pending(documentation, pending)
            pending = nil
          elsif pending
            append_continuation(pending, body, comment)
            next
          end

          if (tag = noncanonical_known_tag(body, raw))
            code = (tag == "@extrbs") ? "extrbs.noncanonical-spacing" : "documentation.noncanonical-spacing"
            message = (tag == "@extrbs") ? "Write @extrbs as '# @extrbs' with one space." : "Write ZARD annotations immediately after '# '."
            add_diagnostic(code, :warning, message, comment.location)
            pending = pending_documentation(raw_tag(body, raw, comment.location), comment)
            seen_non_extrbs_annotation = true
            next
          end

          if non_utf8_documentation?(body, raw)
            add_diagnostic(
              "documentation.non-utf8",
              :error,
              "ZARD documentation requires UTF-8 source text.",
              comment.location
            )
            pending = pending_documentation(raw_tag(body, raw, comment.location), comment)
            seen_non_extrbs_annotation = true
            next
          end

          if (payload = contract_payload(body, "@extrbs"))
            if seen_non_extrbs_annotation
              add_diagnostic(
                "extrbs.not-first",
                :warning,
                "Place @extrbs before the other annotations in this comment block.",
                comment.location
              )
            end
            contracts << contract(:extrbs, payload, raw, comment.location)
          elsif (payload = contract_payload(body, "@rbs"))
            contracts << contract(:rbs, payload, raw, comment.location)
            seen_non_extrbs_annotation = true
          elsif raw.start_with?("#:")
            contracts << contract(:rbs, raw.delete_prefix("#:").strip, raw, comment.location)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@param(?:\s|\z)/)
            pending = pending_documentation(parse_named_tag(body, raw, comment.location, :param, "@param"), comment)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@yieldparam(?:\s|\z)/)
            pending = pending_documentation(parse_named_tag(body, raw, comment.location, :yieldparam, "@yieldparam"), comment)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@option(?:\s|\z)/)
            pending = pending_documentation(parse_option(body, raw, comment.location), comment)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@raise(?:\s|\z)/)
            pending = pending_documentation(parse_named_tag(body, raw, comment.location, :raise, "@raise"), comment)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@return(?:\s|\z)/)
            pending = pending_documentation(parse_nameless_tag(body, raw, comment.location, :return, "@return"), comment)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@yieldreturn(?:\s|\z)/)
            pending = pending_documentation(parse_nameless_tag(body, raw, comment.location, :yieldreturn, "@yieldreturn"), comment)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@note(?:\s|\z)/)
            pending = pending_documentation(parse_description_tag(body, raw, comment.location, :note, "@note"), comment)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@see(?:\s|\z)/)
            pending = pending_documentation(parse_description_tag(body, raw, comment.location, :see, "@see"), comment)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@deprecated(?:\s|\z)/)
            pending = pending_documentation(parse_description_tag(body, raw, comment.location, :deprecated, "@deprecated"), comment)
            seen_non_extrbs_annotation = true
          elsif body.match?(/\A@example(?:\s|\z)/)
            pending = pending_documentation(parse_description_tag(body, raw, comment.location, :example, "@example"), comment)
            seen_non_extrbs_annotation = true
          elsif body.start_with?("@")
            pending = pending_documentation(raw_tag(body, raw, comment.location), comment)
            seen_non_extrbs_annotation = true
          elsif !body.empty?
            documentation << documentation_tag(:text, nil, nil, body, raw, comment.location)
          end
        end

        flush_pending(documentation, pending)

        {documentation: documentation, contracts: contracts}
      end

      private

      def comment_body(raw)
        raw.sub(/\A# ?/, "").delete_suffix("\r")
      end

      def annotation_boundary?(body, raw)
        raw.start_with?("#:", "# @") || !noncanonical_known_tag(body, raw).nil?
      end

      def noncanonical_known_tag(body, raw)
        return if raw.start_with?("# @")

        candidate = body.lstrip[/\A@[^\s]*/]
        return unless %w[@extrbs @rbs @param @yieldparam @option @raise @return @yieldreturn @note @see @deprecated @example].include?(candidate)

        candidate
      end

      def pending_documentation(tag, comment)
        lines = tag.description.strip.empty? ? [] : [tag.description]
        {tag: tag, comments: [comment], lines: lines}
      end

      def append_continuation(pending, body, comment)
        pending.fetch(:lines) << (body.strip.empty? ? "" : body)
        pending.fetch(:comments) << comment
      end

      def flush_pending(documentation, pending)
        return unless pending

        lines = pending.fetch(:lines)
        lines.shift while lines.first == ""
        lines.pop while lines.last == ""
        tag = pending.fetch(:tag)
        comments = pending.fetch(:comments)
        description = lines.join("\n")
        location = comments.first.location

        if tag.name != :raw && description.empty?
          add_diagnostic(
            "documentation.empty-description",
            :warning,
            "Add a description to this ZARD documentation tag.",
            location
          )
        end

        documentation << Model::V1::DocumentationTag.new(
          name: tag.name,
          owner: tag.owner,
          subject: tag.subject,
          claim: tag.claim,
          description: description,
          span: combined_span(comments),
          raw: combined_raw(comments)
        )
      end

      def combined_span(comments)
        first = comments.first.location
        last = comments.last.location
        Model::V1::SourceSpan.new(
          path: @path,
          start_line: first.start_line,
          start_column: first.start_column,
          end_line: last.end_line,
          end_column: last.end_column,
          start_offset: first.start_offset,
          end_offset: last.end_offset
        )
      end

      def combined_raw(comments)
        first = comments.first.location.start_offset
        last = comments.last.location.end_offset
        @source.byteslice(first, last - first)
      end

      def contract_payload(body, tag)
        match = body.match(/\A#{Regexp.escape(tag)}(?:\s+(.*)|\z)/)
        match && match[1].to_s
      end

      def non_utf8_documentation?(body, raw)
        return false if @encoding == Encoding::UTF_8
        return false if body.empty?
        return false if contract_payload(body, "@extrbs") || contract_payload(body, "@rbs")
        return false if raw.start_with?("#:")

        true
      end

      def contract(channel, payload, raw, location)
        contract_payload, marker, note = payload.partition(" -- ")
        Model::V1::Contract.new(
          channel: channel,
          payload: contract_payload,
          note: marker.empty? ? nil : note,
          span: span(location),
          raw: raw
        )
      end

      def parse_named_tag(body, raw, location, name, prefix)
        rest = body.delete_prefix(prefix).sub(/\A[\t ]/, "")
        head, description = split_named_description(rest)

        unless head
          yard_like(raw, location)
          return raw_tag(body, raw, location)
        end

        subject, claim, valid = parse_named_head(head)
        unless valid
          yard_like(raw, location)
          return raw_tag(body, raw, location)
        end

        documentation_tag(name, subject, claim, description, raw, location)
      end

      def parse_option(body, raw, location)
        rest = body.delete_prefix("@option").sub(/\A[\t ]/, "")
        head, description = split_named_description(rest)
        unless head
          yard_like(raw, location)
          return raw_tag(body, raw, location)
        end

        owner, option_head = head.split(/\s+/, 2)
        subject, claim, valid = parse_named_head(option_head.to_s)

        if !owner || !valid
          yard_like(raw, location)
          return raw_tag(body, raw, location)
        end

        documentation_tag(:option, subject, claim, description, raw, location, owner: owner)
      end

      def parse_nameless_tag(body, raw, location, name, prefix)
        rest = body.delete_prefix(prefix).sub(/\A[\t ]/, "")

        if rest == "—" || rest.start_with?("— ")
          add_diagnostic(
            "documentation.redundant-marker",
            :warning,
            "Remove the redundant em dash from #{prefix} without a type claim.",
            location
          )
          description = rest.delete_prefix("—").sub(/\A /, "")
          return documentation_tag(name, nil, nil, description, raw, location)
        end

        if rest.start_with?("[")
          claim, remainder = bracketed_claim(rest)
          valid_claim = claim && (remainder == " —" || remainder.start_with?(" — "))
          if !valid_claim
            yard_like(raw, location)
            return raw_tag(body, raw, location)
          end

          description = remainder.delete_prefix(" —").sub(/\A /, "")
          return documentation_tag(name, nil, claim, description, raw, location)
        end

        documentation_tag(name, nil, nil, rest, raw, location)
      end

      def parse_description_tag(body, raw, location, name, prefix)
        description = body.delete_prefix(prefix).sub(/\A[\t ]/, "")
        documentation_tag(name, nil, nil, description, raw, location)
      end

      def split_named_description(rest)
        match = rest.match(/\A(.+?) —(?: (.*))?\z/)
        return [nil, nil] unless match

        [match[1], match[2].to_s]
      end

      def parse_named_head(head)
        subject, remainder = head.split(/\s+/, 2)
        return [nil, nil, false] unless subject
        return [subject, nil, true] unless remainder

        claim, trailing = bracketed_claim(remainder)
        return [subject, claim, true] if claim && trailing.empty?

        [subject, nil, false]
      end

      def bracketed_claim(text)
        return [nil, text] unless text.start_with?("[")

        depth = 0
        text.each_char.with_index do |character, index|
          depth += 1 if character == "["
          depth -= 1 if character == "]"
          next unless depth.zero?

          return [text[1...index], text[(index + 1)..]]
        end

        [nil, text]
      end

      def yard_like(raw, location)
        add_diagnostic(
          "documentation.yard-like",
          :warning,
          "This tag is preserved as raw text because it does not use the ZARD em dash marker.",
          location
        )
      end

      def raw_tag(body, raw, location)
        documentation_tag(:raw, nil, nil, body, raw, location)
      end

      def documentation_tag(name, subject, claim, description, raw, location, owner: nil)
        Model::V1::DocumentationTag.new(
          name: name,
          owner: owner,
          subject: subject,
          claim: claim,
          description: description,
          span: span(location),
          raw: raw
        )
      end

      def add_diagnostic(code, severity, message, location)
        @diagnostics << Model::V1::Diagnostic.new(
          code: code,
          severity: severity,
          message: message,
          span: span(location)
        )
      end

      def span(location)
        Model::V1::SourceSpan.new(
          path: @path,
          start_line: location.start_line,
          start_column: location.start_column,
          end_line: location.end_line,
          end_column: location.end_column,
          start_offset: location.start_offset,
          end_offset: location.end_offset
        )
      end
    end
  end
end
