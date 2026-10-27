# rbs_inline: enabled

module Shared
  # A type documented by the shared dependency.
  class Thing
    # Names its own direct dependency and, through the cycle, app.
    #: (Far far) -> App::Foo
    def link(far) = App::Foo.new
  end
end

module App
  # Shares its name with the app declaration.
  class Common
  end
end
