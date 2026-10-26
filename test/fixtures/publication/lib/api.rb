# @api internal — Container implementation details.
class HiddenBase
  # @api public — Extension point inside an internal container.
  def hook
  end

  # @api internal — Internal helper.
  def helper
  end

  # Nested namespace remains independently publishable.
  class Nested
  end
end

# @api internal — An entirely excluded namespace.
class InternalOnly
end

# Calls [m:HiddenBase#hook], [m:HiddenBase#helper] and [c:InternalOnly].
class API < HiddenBase
  # @deprecated Use **modern** and [m:API#modern].
  #
  # - Keeps Markdown lists and `literal` code.
  # - Literal reference: `[m:API#modern]`.
  def old
  end

  # Supported entry point.
  def modern
  end

  # @api internal — Ruby-public implementation API.
  def implementation
  end

  # @api internal
  def yard_compatibility
  end

  private

  # @api public — Documented private integration point.
  def private_hook
  end

  protected

  # Protected integration point.
  def protected_hook
  end
end
