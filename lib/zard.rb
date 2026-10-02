# frozen_string_literal: true

require_relative "zard/version"
require_relative "zard/model/v1"
require_relative "zard/parsing/parser"

module Zard
  class Error < StandardError; end

  def self.parse(source, path:)
    Parsing::Parser.call(source, path: path)
  end

  private_constant :Parsing
end
