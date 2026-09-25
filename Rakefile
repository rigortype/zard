# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "standard/rake"

Minitest::TestTask.create

desc "Validate RBS signatures"
task :rbs do
  sh "bundle exec rbs -I sig validate"
end

task default: %i[test standard rbs build]
