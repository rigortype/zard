# frozen_string_literal: true

require_relative "lib/zard/version"

Gem::Specification.new do |spec|
  spec.name = "zard"
  spec.version = Zard::VERSION
  spec.authors = ["USAMI Kenta"]
  spec.email = ["tadsan@zonu.me"]

  spec.summary = "AI-friendly Ruby documentation built on RBS and Rigor extensions"
  spec.description = "ZARD models Ruby declarations, API documentation, and RBS or Rigor contract text with source provenance."
  spec.homepage = "https://github.com/rigortype/zard"
  spec.license = "MPL-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["{lib,sig,docs,examples}/**/*", "CONTEXT.md", "CHANGELOG.md", "LICENSE", "README.md"].select { |path| File.file?(path) }.sort
  spec.require_paths = ["lib"]

  spec.add_dependency "prism", "~> 1.9"
end
