# frozen_string_literal: true

require "test_helper"
require "zard/doc/build"
require "tmpdir"
require "fileutils"

class BuildStorageTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("zard-storage-")
    @docroot = File.join(@directory, "docs")
    @publisher = Zard::Doc.const_get(:BuildPublisher).new(@docroot)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_regeneration_preserves_guides_removes_stale_pages_and_rejects_edits
    @publisher.publish({"app/old.md" => "old"}, scopes: {"app" => "app"})
    File.write(File.join(@docroot, "guide.md"), "handwritten")
    @publisher.publish({"app/new.md" => "new"}, scopes: {"app" => "app"})
    refute File.exist?(File.join(@docroot, "app/old.md"))
    assert_equal "handwritten", File.read(File.join(@docroot, "guide.md"))
    File.write(File.join(@docroot, "app/new.md"), "edited")
    assert_raises(Zard::Doc.const_get(:BuildError)) { @publisher.publish({}) }
    assert_equal "edited", File.read(File.join(@docroot, "app/new.md"))
  end

  def test_partial_build_preserves_other_scopes_and_removes_old_destination
    @publisher.publish({"one/a.md" => "one", "two/a.md" => "two"}, scopes: {"one" => "one", "two" => "two"})
    @publisher.publish({"moved/b.md" => "new"}, selected_scopes: {"one" => "moved"})
    assert_equal "two", File.read(File.join(@docroot, "two/a.md"))
    refute File.exist?(File.join(@docroot, "one/a.md"))
    assert_equal({"one" => "moved", "two" => "two"}, @publisher.scopes)
  end

  def test_unowned_and_symlink_paths_are_rejected
    FileUtils.mkdir_p(@docroot)
    File.write(File.join(@docroot, "guide.md"), "same")
    assert_raises(Zard::Doc.const_get(:BuildError)) { @publisher.publish({"guide.md" => "same"}) }
    File.symlink(@directory, File.join(@docroot, "escape"))
    assert_raises(Zard::Doc.const_get(:BuildError)) { @publisher.publish({"escape/page.md" => "bad"}) }
    assert_raises(Zard::Doc.const_get(:BuildError)) { @publisher.publish({"../page.md" => "bad"}) }
    refute File.exist?(File.join(@directory, "page.md"))
  end

  def test_invalid_manifest_cannot_claim_handwritten_pages
    FileUtils.mkdir_p(@docroot)
    File.write(File.join(@docroot, ".zard-manifest.json"), '{"version":1,"pages":{"guide.md":"bad"},"scopes":{}}')
    assert_raises(Zard::Doc.const_get(:BuildError)) { @publisher.publish({}) }
  end

  def test_failed_publication_restores_existing_files
    @publisher.publish({"a.md" => "old", "b.md" => "old"})
    original = File.method(:rename)
    failing = lambda do |source, target|
      raise Errno::EIO, "injected publication failure" if target.end_with?("b.md")
      original.call(source, target)
    end
    File.stub(:rename, failing) do
      error = assert_raises(Zard::Doc.const_get(:BuildError)) { @publisher.publish({"a.md" => "new", "b.md" => "new"}) }
      assert_includes error.message, "previous pages restored"
    end
    assert_equal "old", File.read(File.join(@docroot, "a.md"))
    assert_equal "old", File.read(File.join(@docroot, "b.md"))
    @publisher.publish({"a.md" => "after"})
    assert_equal "after", File.read(File.join(@docroot, "a.md"))
  end

  def test_failed_recovery_retains_actionable_backup
    @publisher.publish({"a.md" => "old", "b.md" => "old"})
    original_rename = File.method(:rename)
    original_copy = FileUtils.method(:cp)
    File.stub(:rename, lambda { |source, target| target.end_with?("b.md") ? raise(Errno::EIO, "publish") : original_rename.call(source, target) }) do
      FileUtils.stub(:cp, lambda { |source, target| source.include?("/backup/") ? raise(Errno::EIO, "restore") : original_copy.call(source, target) }) do
        error = assert_raises(Zard::Doc.const_get(:BuildError)) { @publisher.publish({"a.md" => "new", "b.md" => "new"}) }
        assert_includes error.message, "recovery failed"
        backup = error.message.split("restore files from ").last
        assert_equal "old", File.read(File.join(backup, "a.md"))
      end
    end
  end

  def test_configuration_dependency_cycles_and_source_assignment_deduplication
    FileUtils.mkdir_p(File.join(@directory, "lib"))
    File.write(File.join(@directory, "lib/a.rb"), "class A; end")
    File.write(File.join(@directory, "lib/ignored.rb"), "class Ignored; end")
    config = {"docroot" => "docs", "scopes" => {"app" => {"destination" => "app", "references" => ["shared"], "sources" => [{"root" => "lib", "exclude" => ["ignored.rb"]}]}, "shared" => {"destination" => "shared", "references" => ["app"], "sources" => [{"root" => "lib"}]}}}
    path = File.join(@directory, "zard.yml")
    File.write(path, YAML.dump(config))
    built = Zard::Doc.const_get(:BuildConfiguration).new(path, scopes: ["app"])
    assert_equal %w[app shared], built.selected_scopes
    assert_equal({File.realpath(File.join(@directory, "lib/a.rb")) => "a.md"}, built.source_files("app"))
    config["scopes"]["app"]["sources"] << {"root" => "lib", "exclude" => ["ignored.rb"]}
    File.write(path, YAML.dump(config))
    assert_equal 1, Zard::Doc.const_get(:BuildConfiguration).new(path).source_files("app").length
    config["scopes"]["app"]["sources"][1] = {"root" => "lib", "prefix" => "different"}
    File.write(path, YAML.dump(config))
    assert_raises(Zard::Doc.const_get(:BuildError)) { Zard::Doc.const_get(:BuildConfiguration).new(path).source_files("app") }
  end

  def test_invalid_configuration_and_escaping_source_symlinks
    FileUtils.mkdir_p(File.join(@directory, "lib"))
    path = File.join(@directory, "zard.yml")
    valid = {"docroot" => "docs", "scopes" => {"app" => {"destination" => "app", "sources" => [{"root" => "lib"}]}}}
    [valid.merge("unknown" => true), valid.merge("layout" => "invalid"), valid.merge("scopes" => {})].each do |data|
      File.write(path, YAML.dump(data))
      assert_raises(Zard::Doc.const_get(:BuildError)) { Zard::Doc.const_get(:BuildConfiguration).new(path) }
    end
    File.write(path, "docroot: first\ndocroot: second\nscopes: {}\n")
    assert_raises(Zard::Doc.const_get(:BuildError)) { Zard::Doc.const_get(:BuildConfiguration).new(path) }
    File.write(path, YAML.dump(valid))
    assert_raises(Zard::Doc.const_get(:BuildError)) { Zard::Doc.const_get(:BuildConfiguration).new(path).source_files("app") }
    File.write(File.join(@directory, "outside.rb"), "class Outside; end")
    File.symlink(File.join(@directory, "outside.rb"), File.join(@directory, "lib/link.rb"))
    assert_raises(Zard::Doc.const_get(:BuildError)) { Zard::Doc.const_get(:BuildConfiguration).new(path).source_files("app") }
  end

  def test_documentation_root_symlink_is_rejected_but_temporary_directory_aliases_work
    @publisher.publish({"page.md" => "temporary"})
    assert_equal "temporary", File.read(File.join(@docroot, "page.md"))
    link = File.join(@directory, "linked-docroot")
    File.symlink(@docroot, link)
    assert_raises(Zard::Doc.const_get(:BuildError)) { Zard::Doc.const_get(:BuildPublisher).new(link) }
    Dir.mktmpdir("zard-alias-", "/tmp") do |directory|
      Zard::Doc.const_get(:BuildPublisher).new(File.join(directory, "docs")).publish({"page.md" => "alias"})
      assert_equal "alias", File.read(File.join(directory, "docs/page.md"))
    end
  end

  def test_case_collisions_are_detected_with_a_numeric_existing_parent
    numeric = File.join(@directory, "123")
    FileUtils.mkdir_p(numeric)
    target = File.join(numeric, "docs/api")
    publisher = Zard::Doc.const_get(:BuildPublisher).new(target)
    parent = File.realpath(@directory)
    alternate = File.join(File.dirname(parent), File.basename(parent).swapcase)
    pages = {"app/Foo.md" => "one", "app/foo.md" => "two"}
    if File.exist?(alternate) && File.identical?(parent, alternate)
      error = assert_raises(Zard::Doc.const_get(:BuildError)) { publisher.publish(pages, scopes: {"app" => "app"}) }
      assert_includes error.message, "collide"
      refute File.exist?(target)
    else
      publisher.publish(pages, scopes: {"app" => "app"})
      assert_equal "one", File.read(File.join(target, "app/Foo.md"))
      assert_equal "two", File.read(File.join(target, "app/foo.md"))
    end
  end
end
