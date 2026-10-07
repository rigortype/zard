# frozen_string_literal: true

module Zard
  module Model
    module V1
      class SourceSpan
        attr_reader :path, :start_line, :start_column, :end_line, :end_column, :start_offset, :end_offset

        def initialize(path:, start_line:, start_column:, end_line:, end_column:, start_offset:, end_offset:)
          @path = path
          @start_line = start_line
          @start_column = start_column
          @end_line = end_line
          @end_column = end_column
          @start_offset = start_offset
          @end_offset = end_offset
          freeze
        end
      end

      class Diagnostic
        attr_reader :code, :severity, :message, :span

        def initialize(code:, severity:, message:, span:)
          @code = code
          @severity = severity
          @message = message
          @span = span
          freeze
        end
      end

      class Contract
        attr_reader :channel, :payload, :note, :span, :raw

        def initialize(channel:, payload:, note:, span:, raw:)
          @channel = channel
          @payload = payload
          @note = note
          @span = span
          @raw = raw
          freeze
        end
      end

      class DocumentationTag
        attr_reader :name, :owner, :subject, :claim, :description, :span, :raw

        def initialize(name:, owner:, subject:, claim:, description:, span:, raw:)
          @name = name
          @owner = owner
          @subject = subject
          @claim = claim
          @description = description
          @span = span
          @raw = raw
          freeze
        end
      end

      class MixinReference
        attr_reader :kind, :target, :span

        def initialize(kind:, target:, span:)
          @kind = kind
          @target = target
          @span = span
          freeze
        end
      end

      class Declaration
        attr_reader :kind, :name, :namespace, :visibility, :parameters, :receiver, :receiver_span, :refinement, :refinement_span, :alias_target, :superclass, :superclass_span, :class_builder, :class_builder_span, :mixins, :span, :comment_span, :documentation, :contracts

        def initialize(kind:, name:, namespace:, visibility:, parameters:, span:, comment_span:, documentation:, contracts:, receiver: nil, receiver_span: nil, refinement: nil, refinement_span: nil, alias_target: nil, superclass: nil, superclass_span: nil, class_builder: nil, class_builder_span: nil, mixins: [].freeze)
          @kind = kind
          @name = name
          @namespace = namespace
          @visibility = visibility
          @parameters = parameters
          @receiver = receiver
          @receiver_span = receiver_span
          @refinement = refinement
          @refinement_span = refinement_span
          @alias_target = alias_target
          @superclass = superclass
          @superclass_span = superclass_span
          @class_builder = class_builder
          @class_builder_span = class_builder_span
          @mixins = mixins
          @span = span
          @comment_span = comment_span
          @documentation = documentation
          @contracts = contracts
          freeze
        end
      end

      class Document
        attr_reader :path, :declarations, :diagnostics

        def initialize(path:, declarations:, diagnostics:)
          @path = path
          @declarations = declarations
          @diagnostics = diagnostics
          freeze
        end
      end
    end
  end
end
