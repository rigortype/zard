# frozen_string_literal: true

require "test_helper"
require "zard/doc/build"

class BuildRendererTest < Minitest::Test
  def document(source, path)
    Zard.parse(source, path: File.expand_path(path))
  end

  def renderer(documents, references: {}, layout: "namespace", files: {})
    scopes = documents.to_h { |name, _| [name, {destination: name, references: references.fetch(name, [])}] }
    mappings = documents.to_h { |name, docs| [name, docs.to_h { |doc| [doc.path, files.fetch(doc.path, File.basename(doc.path, ".rb") + ".md")] }] }
    Zard::Doc.const_get(:BuildRenderer).new(scope_documents: documents, scope_files: mappings, scopes: scopes, layout: layout)
  end

  def test_shared_documents_have_scope_specific_links_and_navigation
    shared = document("# See [m:Same#run].\nclass Same\n # Runs.\n def run; end\nend", "shared.rb")
    pages = renderer({"one" => [shared], "two" => [shared]}).render
    assert_includes pages.fetch("one/Same.md"), "[Same#run](Same.md#zard-"
    assert_includes pages.fetch("two/Same.md"), "[Same#run](Same.md#zard-"
    refute_includes pages.fetch("one/Same.md"), "two/"
    assert_includes pages.fetch("index.md"), "[one](one/index.md)"
    assert_includes pages.fetch("two/index.md"), "[Same.md](Same.md)"
  end

  def test_reopenings_retain_provenance_and_duplicate_methods_are_ambiguous
    first = document("# First [c:Same].\nclass Same\n # First run.\n def run; end\nend", "first.rb")
    second = document("# Second [m:Same#run].\nclass Same\n # Second run.\n def run; end\nend", "second.rb")
    build = renderer({"app" => [first, second]})
    page = build.render.fetch("app/Same.md")
    assert_includes page, "First [Same](Same.md#zard-"
    assert_includes page, "Second [m:Same#run]"
    assert_includes page, "first.rb:2"
    assert_includes page, "second.rb:2"
    anchors = page.scan(/<a id="([^"]+)"/).flatten
    assert_equal 4, anchors.length
    assert_equal anchors.uniq, anchors
    assert_match(/app:.*first.rb:4.*app:.*second.rb:4/, build.diagnostics.join)
  end

  def test_direct_dependency_links_and_transitive_visibility
    app = document("# [c:Direct] [c:Hidden]\nclass App; end", "app.rb")
    direct = document("# Direct.\nclass Direct; end", "direct.rb")
    hidden = document("# Hidden.\nclass Hidden; end", "hidden.rb")
    pages = renderer({"app" => [app], "dep" => [direct], "deep" => [hidden]}, references: {"app" => ["dep"], "dep" => ["deep"]}).render
    assert_includes pages.fetch("app/App.md"), "[Direct](../dep/Direct.md#zard-"
    assert_includes pages.fetch("app/App.md"), "[c:Hidden]"
  end

  def test_local_undocumented_owner_and_private_member_block_dependencies
    app = document("class Target\n private\n # Secret.\n def run; end\nend\n# [c:Target] [m:Target#run] [m:Target#missing]\nclass App; end", "app.rb")
    dep = document("# Target.\nclass Target\n # Run.\n def run; end\n # Missing.\n def missing; end\nend", "dep.rb")
    page = renderer({"app" => [app], "dep" => [dep]}, references: {"app" => ["dep"]}).render.fetch("app/App.md")
    assert_includes page, "[c:Target] [m:Target#run] [m:Target#missing]"
  end

  def test_dependency_ambiguity_includes_scopes_and_locations
    app = document("# [c:Same]\nclass App; end", "app.rb")
    dep = document("# Shared.\nclass Same; end", "dep.rb")
    build = renderer({"app" => [app], "one" => [dep], "two" => [dep]}, references: {"app" => ["one", "two"]})
    assert_includes build.render.fetch("app/App.md"), "[c:Same]"
    assert_match(/one:.*dep.rb:2.*two:.*dep.rb:2/, build.diagnostics.join)
  end

  def test_absolute_reference_respects_local_owner_shadowing
    app = document("class Target; end\n# [m:::Target#missing] [m:Target#missing]\nclass App; end", "app.rb")
    dependency = document("class Target\n # Missing.\n def missing; end\nend", "dependency.rb")
    page = renderer({"app" => [app], "dep" => [dependency]}, references: {"app" => ["dep"]}).render.fetch("app/App.md")
    assert_includes page, "[m:::Target#missing] [m:Target#missing]"
    refute_includes page, "../dep/"
  end

  def test_repeated_dependency_names_do_not_make_a_target_ambiguous
    app = document("# [c:Target]\nclass App; end", "app.rb")
    dependency = document("# Target.\nclass Target; end", "dependency.rb")
    build = renderer({"app" => [app], "dep" => [dependency]}, references: {"app" => ["dep", "dep"]})
    assert_includes build.render.fetch("app/App.md"), "[Target](../dep/Target.md#zard-"
    assert_empty build.diagnostics
  end

  def test_relative_member_references_respect_the_local_owner
    app = document("# [m:#missing] [m:.missing]\nclass Target; end", "app.rb")
    dependency = document("class Target\n # Missing instance member.\n def missing; end\n # Missing singleton member.\n def self.missing; end\nend", "dependency.rb")
    page = renderer({"app" => [app], "dep" => [dependency]}, references: {"app" => ["dep"]}).render.fetch("app/Target.md")
    assert_includes page, "[m:#missing] [m:.missing]"
    refute_includes page, "../dep/"
  end

  def test_file_layout_prefixes_escaped_paths_and_literal_code
    doc = document("# See [m:Demo#run]; `[m:Demo#run]`.\nclass Demo\n # Runs.\n # @example\n #   [m:Demo#run]\n def run; end\nend", "code.rb")
    empty = document("VALUE = 1", "empty.rb")
    build = renderer({"app" => [doc, empty]}, layout: "file", files: {doc.path => "src/日本 (api).md"})
    page = build.render.fetch("app/src/日本 (api).md")
    assert_includes page, "%E6%97%A5%E6%9C%AC%20%28api%29.md#zard-"
    assert_includes page, "`[m:Demo#run]`"
    assert_includes page, "  [m:Demo#run]"
    refute build.render.key?("app/empty.md")
  end

  def test_top_level_and_undocumented_namespace_members
    doc = document("# Value.\nVALUE = 1\nclass Outer\n # Runs.\n def run; end\nend", "code.rb")
    pages = renderer({"app" => [doc]}).render
    assert_includes pages.fetch("app/_top-level.md"), "Constant `VALUE`"
    assert_includes pages.fetch("app/Outer.md"), "Outer#run"
  end

  def test_unicode_names_operator_anchors_and_contracts
    doc = document("# [m:Étage#\\[\\]]\nclass Étage\n # Reads.\n # @rbs () -> String\n def []; end\nend", "unicode.rb")
    page = renderer({"app" => [doc]}).render.fetch("app/Étage.md")
    assert_includes page, "%C3%89tage.md#zard-"
    refute_includes page, "() -> String"
  end

  def test_refinements_and_dynamic_receivers_do_not_link_to_normal_methods
    doc = document("# API.\nmodule Demo\n # Normal.\n def run; end\n refine String do\n  # [m:Demo#run]\n  def special; end\n end\n object = Object.new\n # Dynamic.\n def object.call; end\n # [m:Demo.call]\n def caller; end\nend", "special.rb")
    page = renderer({"app" => [doc]}).render.fetch("app/Demo.md")
    assert_includes page, "[m:Demo#run]"
    assert_includes page, "[m:Demo.call]"
    assert_includes page, "Demo[String]#special"
  end

  def test_anchors_survive_checkout_and_line_changes_and_layout_switches
    source = "# API [m:Same#run].\nclass Same\n # Runs.\n def run; end\nend"
    original = document(source, "/original/lib/same.rb")
    moved = document("\n\n" + source, "/copied/lib/same.rb")
    namespace_pages = [original, moved].map { |doc| renderer({"app" => [doc]}).render.fetch("app/Same.md") }
    anchors = namespace_pages.map { |page| page.scan(/<a id="([^"]+)"/).flatten }
    assert_equal anchors.first, anchors.last
    file_page = renderer({"app" => [moved]}, layout: "file").render.fetch("app/same.md")
    assert_equal anchors.first, file_page.scan(/<a id="([^"]+)"/).flatten
  end

  def test_duplicate_anchors_use_relative_source_assignments_and_ordinals
    source = "# First.\nclass Same\n # First run.\n def run; end\n # Second run.\n def run; end\nend"
    anchors = ["/original", "/copied"].map do |root|
      doc = document(source, "#{root}/lib/same.rb")
      reopening = document("# Reopened.\nclass Same; end", "#{root}/ext/reopened.rb")
      page = renderer({"app" => [doc, reopening]}).render.fetch("app/Same.md")
      page.scan(/<a id="([^"]+)"/).flatten
    end
    assert_equal anchors.first, anchors.last
    assert_equal 3, anchors.first.uniq.length
  end

  def test_explicit_constant_singleton_receiver_owns_its_namespace_page
    doc = document("class Other; end\n# [m:Other.run].\nclass Caller\n # Runs elsewhere.\n def Other.run; end\nend", "receivers.rb")
    pages = renderer({"app" => [doc]}).render
    assert_includes pages.fetch("app/Other.md"), "Other.run"
    assert_includes pages.fetch("app/Caller.md"), "[Other.run](Other.md#zard-"
    refute_includes pages.fetch("app/Caller.md"), "Runs elsewhere."
  end

  def test_reserved_navigation_and_conflicting_file_assignments_fail
    first = document("# First.\nclass First; end", "first.rb")
    second = document("# Second.\nclass Second; end", "second.rb")
    assert_raises(Zard::Doc.const_get(:BuildError)) { renderer({"app" => [first]}, layout: "file", files: {first.path => "index.md"}).render }
    assert_raises(Zard::Doc.const_get(:BuildError)) { renderer({"app" => [first, second]}, layout: "file", files: {first.path => "same.md", second.path => "same.md"}).render }
  end
end
