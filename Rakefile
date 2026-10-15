# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "standard/rake"

Minitest::TestTask.create

desc "Validate RBS signatures"
task :rbs do
  sh "bundle exec rbs -I sig validate"
end

desc "Build the zard-doc gem"
task :build_doc do
  Dir.chdir("zard-doc") do
    spec = Gem::Specification.load("zard-doc.gemspec")
    sh "gem build zard-doc.gemspec --output ../pkg/#{spec.full_name}.gem"
  end
end

desc "Build the optional zard-rigor gem"
task :build_rigor do
  Dir.chdir("zard-rigor") do
    spec = Gem::Specification.load("zard-rigor.gemspec")
    sh "gem build zard-rigor.gemspec --output ../pkg/#{spec.full_name}.gem"
  end
end

task default: %i[test standard rbs build build_doc build_rigor]
