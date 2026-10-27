# rbs_inline: enabled

module App
  # Signatures naming local, dependency and external types.
  class Service
    # Nested generics, a block and a UTF-8 literal.
    #: (Array[Hash[Symbol, Foo]] items) { (Foo) -> Common } -> (Foo | "ä")?
    def call(items, &block) = nil

    # Direct, transitive and competing dependencies and an interface.
    #: (Shared::Thing thing, Far far, Twin twin, _ToS text) -> String
    def across(thing, far, twin, text) = ""

    # An excluded declaration, an unrelated scope and a Data.define constant.
    #: (Hidden hidden, Lonely lonely) -> Point
    def elsewhere(hidden, lonely) = Point.new(x: 1)

    # Inferred return.
    def make = Foo.new

    # Overloaded in sig/service.rbs.
    def convert(value) = value
  end
end
