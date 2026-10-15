# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tmpdir"
require "fileutils"
require "yaml"
require "json"
require "digest"
require "open3"
require "rbconfig"
require "zard/doc/cli"

class ZardDocJSONBuildTest < Minitest::Test
  def test_exports_public_declarations_without_requiring_prose_or_running_ruby
    with_project do |root, config|
      code = "raise 'must not execute'\nclass API\n attr_accessor :value\n def run(path, **options); end\n private\n def secret; end\nend\n"
      write_source(root, "lib/api.rb", code)
      write_config(config, {"app" => scope("lib", "app")})

      status, output, errors = run_cli(config)

      assert_equal 0, status, errors
      assert_empty errors
      data = JSON.parse(output)
      assert_equal ["zard-doc/v0", 1], data.values_at("schema", "revision")
      assert_equal Zard::VERSION, data.fetch("producer").fetch("zard")
      app = data.fetch("scopes").first
      assert_equal %w[API value run], app.fetch("declarations").map { |item| item.fetch("name") }
      method = app.fetch("declarations").last
      assert_equal "API#run", method.fetch("display_name")
      assert_equal "app/API.md", method.fetch("page")
      assert_equal "lib/api.rb", method.fetch("span").fetch("path")
      assert_equal "def run(path, **options); end", code.byteslice(method.fetch("span").fetch("start_offset")...method.fetch("span").fetch("end_offset"))
      assert_equal Digest::SHA256.hexdigest(code), app.fetch("files").first.fetch("digest")
      assert_equal app.fetch("declarations").map { |item| item.fetch("id") }, app.fetch("pages").first.fetch("declarations")
      refute_includes output, root
      refute File.exist?(File.join(root, "docs"))
    end
  end

  def test_keeps_contracts_as_text_and_retains_documentation_claims_and_provenance
    with_project do |root, config|
      fixture = File.expand_path("../examples/catalog/lib/catalog/entry.rb", __dir__)
      write_source(root, "lib/entry.rb", File.read(fixture))
      write_config(config, {"app" => scope("lib", "app")})

      status, output, errors = run_cli(config)

      assert_equal 0, status, errors
      declarations = JSON.parse(output).fetch("scopes").first.fetch("declarations")
      item = declarations.find { |entry| entry.fetch("name") == "read_name" }
      original = Zard.parse(File.read(fixture), path: fixture).declarations.find { |entry| entry.name == "read_name" }
      assert_equal original.contracts.map(&:payload), item.fetch("contracts").map { |entry| entry.fetch("payload") }
      assert_equal original.documentation.map(&:description), item.fetch("documentation").map { |entry| entry.fetch("description") }
      assert item.fetch("contracts").all? { |entry| entry.fetch("span").fetch("path") == "lib/entry.rb" }
      refute item.key?("signature")
      refute item.key?("inferred_type")
    end
  end

  def test_reuses_scoped_reference_resolution_and_keeps_repeated_definition_sites
    with_project do |root, config|
      write_source(root, "app/a.rb", "# [m:Core#run] [m:Same#run]\nclass Same\n def run; end\nend\n")
      write_source(root, "app/b.rb", "class Same\n def run; end\nend\n")
      write_source(root, "core/api.rb", "class Core\n def run; end\nend\n")
      write_source(root, "other/api.rb", "class Same\n def run; end\nend\n")
      write_config(config, {"app" => scope("app", "app", ["core"]), "core" => scope("core", "core"), "other" => scope("other", "other")})

      status, output, errors = run_cli(config)

      assert_equal 0, status, errors
      data = JSON.parse(output)
      app = data.fetch("scopes").find { |item| item.fetch("name") == "app" }
      assert_equal 4, app.fetch("declarations").length
      assert_equal 4, app.fetch("declarations").map { |item| item.fetch("id") }.uniq.length
      assert_equal 1, app.fetch("pages").length
      description = app.fetch("declarations").first.fetch("documentation").first.fetch("rendered_description")
      assert_includes description, "../core/Core.md#zard-"
      assert_includes description, "[m:Same#run]"
      assert_equal "core/Core.md", data.fetch("links").fetch("app/Same.md").first.fetch("path")
      assert_match(/ambiguous/, data.fetch("warnings").first)
      refute_includes output, root
      other = data.fetch("scopes").find { |item| item.fetch("name") == "other" }
      assert_empty app.fetch("declarations").map { |item| item.fetch("id") } & other.fetch("declarations").map { |item| item.fetch("id") }
    end
  end

  def test_selected_scope_exports_only_its_recursive_dependency_closure
    with_project do |root, config|
      %w[app core deep other].each { |name| write_source(root, "#{name}/api.rb", "class #{name.capitalize}; end") }
      write_config(config, {"app" => scope("app", "app", ["core"]), "core" => scope("core", "core", ["deep"]), "deep" => scope("deep", "deep", ["app"]), "other" => scope("other", "other")})

      status, output, errors = run_cli(config, "--scope", "app")

      assert_equal 0, status, errors
      assert_equal %w[app core deep], JSON.parse(output).fetch("scopes").map { |item| item.fetch("name") }
    end
  end

  def test_export_is_deterministic_across_checkouts_and_layout_changes_preserve_ids
    exports = 2.times.map do
      with_project do |root, config|
        write_source(root, "lib/api.rb", "class API\n def run; end\n def run; end\nend\n")
        write_config(config, {"app" => scope("lib", "app")})
        status, first, errors = run_cli(config)
        assert_equal 0, status, errors
        assert_equal first, run_cli(config)[1]
        status, file_layout, errors = run_cli(config, "--layout", "file")
        assert_equal 0, status, errors
        namespace = JSON.parse(first).fetch("scopes").first.fetch("declarations")
        files = JSON.parse(file_layout).fetch("scopes").first.fetch("declarations")
        assert_equal namespace.map { |item| item.fetch("id") }, files.map { |item| item.fetch("id") }
        assert_equal ["app/api.md"], files.map { |item| item.fetch("page") }.uniq
        first
      end
    end
    assert_equal exports.first, exports.last
  end

  def test_errors_do_not_emit_partial_json_or_modify_existing_markdown
    with_project do |root, config|
      write_source(root, "lib/api.rb", "# API.\nclass API; end\n")
      write_config(config, {"app" => scope("lib", "app")})
      assert_equal 0, run_cli(config, "--format", "markdown").first
      before = File.binread(File.join(root, "docs/api/app/API.md"))
      assert_equal 0, run_cli(config).first
      assert_equal before, File.binread(File.join(root, "docs/api/app/API.md"))
      write_source(root, "lib/broken.rb", "class Broken(\n")

      status, output, errors = run_cli(config)

      assert_equal 1, status
      assert_empty output
      assert_includes errors, "ruby.syntax"
      assert_equal before, File.binread(File.join(root, "docs/api/app/API.md"))
    end
  end

  def test_invalid_format_is_a_usage_error
    status, output, errors = run_cli("unused.yml", "--format", "unknown")
    assert_equal 2, status
    assert_empty output
    assert_includes errors, "--format"
  end

  def test_executable_emits_one_json_document_with_a_success_status
    with_project do |root, config|
      write_source(root, "lib/api.rb", "class API; end\n")
      write_config(config, {"app" => scope("lib", "app")})
      libraries = %w[lib zard-doc/lib].map { |path| File.expand_path("../#{path}", __dir__) }
      executable = File.expand_path("../zard-doc/exe/zard-doc", __dir__)

      output, errors, process = Open3.capture3(RbConfig.ruby, *libraries.flat_map { |path| ["-I", path] },
        executable, "build", "--config", config, "--format", "json")

      assert process.success?, errors
      assert_empty errors
      assert_equal "API", JSON.parse(output).fetch("scopes").first.fetch("declarations").first.fetch("name")
      refute File.exist?(File.join(root, "docs"))
    end
  end

  def test_json_export_validates_destinations_without_creating_them
    with_project do |root, config|
      write_source(root, "lib/api.rb", "class API; end\n")
      write_config(config, {"one" => scope("lib", "one"), "two" => scope("lib", "one/two")})

      status, output, errors = run_cli(config)

      assert_equal 2, status
      assert_empty output
      assert_includes errors, "overlapping scope destinations"
      refute File.exist?(File.join(root, "docs"))
    end
  end

  private

  def with_project
    Dir.mktmpdir("zard-json") { |root| yield root, File.join(root, "zard-doc.yml") }
  end

  def write_source(root, path, contents)
    destination = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(destination))
    File.write(destination, contents)
  end

  def scope(root, destination, references = [])
    {"destination" => destination, "references" => references, "sources" => [{"root" => root}]}
  end

  def write_config(path, scopes)
    File.write(path, YAML.dump({"docroot" => "docs/api", "scopes" => scopes}))
  end

  def run_cli(config, *arguments)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Zard::Doc::CLI.run(["build", "--config", config, "--format", "json", *arguments], stdout: stdout, stderr: stderr)
    [status, stdout.string, stderr.string]
  end
end
