# rbs_inline: enabled

module App
  # The local value type, reopened in a second file.
  class Foo
    # Returns the receiver.
    #: () -> Foo
    def itself_value = self
  end
end
