# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tmpdir"
require "fileutils"
require "yaml"
require "json"
require "zard/doc/cli"

class ZardDocBuildCLITest < Minitest::Test
  def test_build_isolates_apps_and_links_to_direct_dependencies
    with_project do |root, config|
      source(root, "core/lib/core.rb", "# Shared core.\nmodule Core\n  # Run.\n  def self.run = nil\nend\n")
      source(root, "app/lib/app.rb", "# App.\n# @see Core.run\nclass App\n  # Local run.\n  def run = nil\nend\n")
      source(root, "other/lib/other.rb", "# Other app.\nclass App\n  # Other run.\n  def run = nil\nend\n")
      write_config(config, {
        "core" => scope("core/lib"),
        "app" => scope("app/lib", references: ["core"]),
        "other" => scope("other/lib")
      })

      status, stdout, stderr = run_cli("build", "--config", config)

      assert_equal 0, status, stderr
      assert_empty stdout
      app = File.read(File.join(root, "docs/api/app/App.md"))
      assert_includes app, "../core/Core.md#"
      assert_includes app, "Local run."
      refute_includes app, "Other run."
      assert File.file?(File.join(root, "docs/api/other/App.md"))
      assert File.file?(File.join(root, "docs/api/index.md"))
    end
  end

  def test_selected_scope_build_includes_dependencies_and_retains_other_outputs
    with_project do |root, config|
      %w[core app other].each { |name| source(root, "#{name}/lib/code.rb", "# #{name}.\nclass #{name.capitalize}; end\n") }
      scopes = {"core" => scope("core/lib"), "app" => scope("app/lib", references: ["core"]), "other" => scope("other/lib")}
      write_config(config, scopes)
      assert_equal 0, run_cli("build", "--config", config).first
      other = File.join(root, "docs/api/other/Other.md")
      original = File.binread(other)
      source(root, "app/lib/code.rb", "# Updated app.\nclass App; end\n")

      status, _, stderr = run_cli("build", "--config", config, "--scope", "app", "--layout", "file")

      assert_equal 0, status, stderr
      assert File.file?(File.join(root, "docs/api/core/code.md"))
      assert File.file?(File.join(root, "docs/api/app/code.md"))
      refute File.exist?(File.join(root, "docs/api/app/App.md"))
      assert_equal original, File.binread(other)
      assert_includes File.read(File.join(root, "docs/api/index.md")), "other/index.md"
    end
  end

  def test_errors_in_any_selected_source_preserve_previous_output
    with_project do |root, config|
      source(root, "one/lib/code.rb", "# One.\nclass One; end\n")
      source(root, "two/lib/code.rb", "# Two.\nclass Two; end\n")
      write_config(config, {"one" => scope("one/lib"), "two" => scope("two/lib")})
      assert_equal 0, run_cli("build", "--config", config).first
      before = output_snapshot(root)
      source(root, "one/lib/code.rb", "# Changed.\nclass One; end\n")
      source(root, "two/lib/code.rb", "class Two(\n")

      status, stdout, stderr = run_cli("build", "--config", config)

      assert_equal 1, status
      assert_empty stdout
      assert_includes stderr, "ruby.syntax"
      assert_equal before, output_snapshot(root)
    end
  end

  def test_modified_pages_and_unowned_collisions_are_not_overwritten
    with_project do |root, config|
      source(root, "app/lib/code.rb", "# App.\nclass App; end\n")
      write_config(config, {"app" => scope("app/lib")})
      assert_equal 0, run_cli("build", "--config", config).first
      page = File.join(root, "docs/api/app/App.md")
      File.write(page, "Hand edited.\n")

      status, _, stderr = run_cli("build", "--config", config)

      assert_equal 2, status, stderr
      assert_equal "Hand edited.\n", File.read(page)
      FileUtils.rm_rf(File.join(root, "docs/api"))
      FileUtils.mkdir_p(File.dirname(page))
      File.write(page, "Handwritten.\n")
      assert_equal 2, run_cli("build", "--config", config).first
      assert_equal "Handwritten.\n", File.read(page)
    end
  end

  def test_exclusions_empty_scripts_and_top_level_page
    with_project do |root, config|
      source(root, "app/lib/code.rb", "# Top-level value.\nVALUE = 1\n# Reads.\ndef read = nil\n")
      source(root, "app/lib/script.rb", "puts :hello\n")
      source(root, "app/lib/fixtures/bad.rb", "class Broken(\n")
      write_config(config, {"app" => scope("app/lib", exclude: ["fixtures/**"])})

      status, _, stderr = run_cli("build", "--config", config)

      assert_equal 0, status, stderr
      top = File.read(File.join(root, "docs/api/app/_top-level.md"))
      assert_includes top, "VALUE"
      assert_includes top, "read()"
      refute File.exist?(File.join(root, "docs/api/app/script.md"))
      refute File.exist?(File.join(root, "docs/api/app/fixtures"))
    end
  end

  def test_build_requires_explicit_config_and_valid_cli_options
    [[], ["--config", "missing.yml"], ["--layout", "unknown"], ["--config", "x.yml", "input.rb"]].each do |arguments|
      status, stdout, stderr = run_cli("build", *arguments)
      assert_equal 2, status
      assert_empty stdout
      refute_empty stderr
    end
  end

  private

  def run_cli(*arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Zard::Doc::CLI.run(arguments, stdout: stdout, stderr: stderr)
    [status, stdout.string, stderr.string]
  end

  def with_project
    Dir.mktmpdir("zard-build-cli") do |root|
      yield root, File.join(root, "zard-doc.yml")
    end
  end

  def source(root, path, contents)
    path = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def scope(root, references: [], exclude: [])
    {"destination" => root.split("/").first, "references" => references,
     "sources" => [{"root" => root, "include" => ["**/*.rb"], "exclude" => exclude}]}
  end

  def write_config(path, scopes)
    File.write(path, YAML.dump({"docroot" => "docs/api", "layout" => "namespace", "scopes" => scopes}))
  end

  def output_snapshot(root)
    Dir.glob(File.join(root, "docs/api/**/*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h { |path| [path, File.binread(path)] }
  end
end
