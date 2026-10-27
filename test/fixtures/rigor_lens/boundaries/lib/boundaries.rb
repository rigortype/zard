# rbs_inline: enabled

class Target
  def self.identity(value) = value
end

module Boundary
  def Target.identity(value) = value.to_s

  def self.identity(value) = value

  refine String do
    def identity(value) = value
  end

  refine Integer do
    def identity(value) = value
  end
end

class Signatures
  def convert(value) = value

  def transform(value, &block) = block.call(value)

  # @extrbs (String value) -> Integer
  def reserved(value) = value
end
