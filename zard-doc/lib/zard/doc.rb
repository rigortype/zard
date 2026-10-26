# frozen_string_literal: true

require "zard"
require_relative "doc/version"
require_relative "doc/reference_markup"
require_relative "doc/publication_policy"
require_relative "doc/renderer"

module Zard
  module Doc
    def self.render(document)
      Renderer.render(document)
    end

    private_constant :Renderer, :ReferenceMarkup, :PublicationPolicy
  end
end
