# Public reopening, with its own provenance.
class API
  # Repeated method definition stays a separate declaration.
  def modern
  end
end

# @api internal — Exclude this reopening only.
class API
  # Independently published member of an excluded reopening.
  def extension
  end
end

module Other
  # A same-named class in a separate namespace.
  class API
  end
end
