# rbs_inline: enabled

module App
  # The local value type.
  class Foo
  end

  # Declared here and in the shared dependency.
  class Common
  end

  # @api internal — Excluded from publication.
  class Hidden
  end

  # A value class built from Data.define.
  Point = Data.define(:x)

  # A generic container.
  #
  # @rbs generic T
  class Box
    # Returns the held value.
    #: () -> T
    def get = nil

    # Maps the held value.
    #: [U] (U seed) { (T) -> U } -> Hash[Symbol, Foo | U]
    def map(seed) = {}
  end
end
