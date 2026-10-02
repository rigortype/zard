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
        attr_reader :channel, :payload, :span, :raw

        def initialize(channel:, payload:, span:, raw:)
          @channel = channel
          @payload = payload
          @span = span
          @raw = raw
          freeze
        end
      end

      class DocumentationTag
        attr_reader :name, :subject, :claim, :description, :span, :raw

        def initialize(name:, subject:, claim:, description:, span:, raw:)
          @name = name
          @subject = subject
          @claim = claim
          @description = description
          @span = span
          @raw = raw
          freeze
        end
      end

      class Declaration
        attr_reader :kind, :name, :namespace, :parameters, :span, :comment_span, :documentation, :contracts

        def initialize(kind:, name:, namespace:, parameters:, span:, comment_span:, documentation:, contracts:)
          @kind = kind
          @name = name
          @namespace = namespace
          @parameters = parameters
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
