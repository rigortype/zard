# frozen_string_literal: true

module Zard
  module Doc
    class PublicationPolicy
      DEFAULT = {visibility: ["public"].freeze, intent: ["public"].freeze}.freeze

      def self.intent(declaration)
        declaration.documentation.find { |tag| tag.name == :api }&.subject || "public"
      end

      def initialize(configuration = DEFAULT)
        @configuration = configuration
      end

      def include?(declaration)
        @configuration.fetch(:visibility).include?(declaration.visibility.to_s) &&
          @configuration.fetch(:intent).include?(self.class.intent(declaration))
      end
    end
  end
end
