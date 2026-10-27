# frozen_string_literal: true

require_relative "lib/zard/rigor/version"

Gem::Specification.new do |spec|
  spec.name = "zard-rigor"
  spec.version = Zard::Rigor::VERSION
  spec.authors = ["USAMI Kenta"]
  spec.email = ["tadsan@zonu.me"]
  spec.summary = "Experimental Rigor lens adapter for ZARD documentation"
  spec.homepage = "https://github.com/rigortype/zard"
  spec.license = "MPL-2.0"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.{rb,json}", "README.md", "LICENSE"].sort }
  spec.require_paths = ["lib"]
  spec.add_dependency "zard", "~> 0.0.2"
  spec.add_dependency "digest-xxhash", "~> 0.2.9"
  spec.add_dependency "rbs", "~> 4.0"
end
