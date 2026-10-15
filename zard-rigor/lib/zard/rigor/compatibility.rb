# frozen_string_literal: true

require "json"

module Zard
  module Rigor
    module Compatibility
      DATA = JSON.parse(File.read(File.join(__dir__, "compatibility.json"))).freeze

      def self.validate!(document)
        unless document.values_at("schema", "revision") == DATA.values_at("schema", "revision")
          raise Error, "Invalid lens document: unsupported schema/revision"
        end
        producer = document.fetch("producer")
        unless producer.is_a?(Hash) && producer["name"] == DATA.fetch("producer") && DATA.fetch("versions").include?(producer["version"])
          raise Error, "Invalid lens document: supported Rigor versions: #{DATA.fetch("versions").join(", ")}"
        end
      end
    end
  end
end
