# frozen_string_literal: true

require_relative "lib/zard/rigor/version"

Gem::Specification.new do |spec|
  spec.name = "zard-rigor"
  spec.version = Zard::Rigor::VERSION
  spec.authors = ["USAMI Kenta"]
  spec.summary = "Experimental Rigor lens adapter for ZARD documentation"
  spec.homepage = "https://github.com/rigortype/zard"
  spec.license = "MPL-2.0"
  spec.required_ruby_version = ">= 3.2.0"
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.{rb,json}", "README.md", "LICENSE"].sort }
  spec.require_paths = ["lib"]
  spec.add_dependency "zard", "~> 0.0.1"
  spec.add_dependency "digest-xxhash", "~> 0.2.9"
end
