module Catalog
  # A named entry in a catalog.
  # This description continues on a plain comment line
  # until the next annotation or declaration.
  class Entry
    # @extrbs return: non-empty-string
    # @rbs path: String
    # @rbs return: String -- The stored value.
    # @param path — Path to the name file.
    # @return The stored name.
    def self.read_name(path)
      File.read(path).strip
    end

    # @param name — Name to store.
    # @return The new entry.
    def initialize(name)
      @name = name
    end

    # The stored entry name.
    attr_reader :name

    # @return The entry name.
    def label
      name
    end

    # @return The entry name.
    alias_method :title, :label

    # @return Internal identifier.
    def internal_id
      name
    end
    private :internal_id

    protected

    # @return Whether the entry matches.
    def matches?(candidate)
      name == candidate
    end
  end
end
