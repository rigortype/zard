# Documented by a scope that app does not reference.
class Lonely
end

module App
  # Shares its name with app's type in an unrelated scope.
  class Foo
  end
end
