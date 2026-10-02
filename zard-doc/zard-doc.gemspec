# frozen_string_literal: true

require_relative "lib/zard/doc/version"

Gem::Specification.new do |spec|
  spec.name = "zard-doc"
  spec.version = Zard::Doc::VERSION
  spec.authors = ["USAMI Kenta"]
  spec.email = ["tadsan@zonu.me"]

  spec.summary = "Markdown API documentation for ZARD"
  spec.description = "zard-doc renders API documentation from the versioned ZARD document model."
  spec.homepage = "https://github.com/rigortype/zard"
  spec.license = "MPL-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "LICENSE", "README.md"].select { |path| File.file?(path) }.sort
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "zard", "~> 0.1.0"
end
