# frozen_string_literal: true

require "zard"
require_relative "doc/version"
require_relative "doc/renderer"

module Zard
  module Doc
    def self.render(document)
      Renderer.render(document)
    end

    private_constant :Renderer
  end
end
