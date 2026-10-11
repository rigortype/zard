# frozen_string_literal: true

require "test_helper"
require "zard/doc"

class ReferenceMarkupRenderingTest < Minitest::Test
  def test_links_bitclust_and_rd_methods_in_prose_to_one_anchor
    markdown = render("Read [m:Foo#bar] or [[m:Foo#bar]].")

    assert_includes markdown, "Read [Foo#bar](#zard-466f6f23626172) or [Foo#bar](#zard-466f6f23626172)."
    assert_equal 1, markdown.scan('<a id="zard-466f6f23626172"></a>').length
  end

  def test_links_classes_modules_constants_and_class_methods
    markdown = render("[c:Foo] [[c:Kernel]] [m:Foo::LIMIT] [m:Foo.build]")

    assert_includes markdown, "[Foo](#zard-466f6f)"
    assert_includes markdown, "[Kernel](#zard-4b65726e656c)"
    assert_includes markdown, "[Foo::LIMIT](#zard-466f6f3a3a4c494d4954)"
    assert_includes markdown, "[Foo.build](#zard-466f6f2e6275696c64)"
  end

  def test_explicit_module_function_spellings_share_the_shorthand_destination
    markdown = render("[m:Kernel?.puts] [[m:Kernel.#puts]]\n@see Kernel?.puts")

    assert_includes markdown, "[Kernel?.puts](#zard-4b65726e656c2e70757473)"
    assert_includes markdown, "[Kernel.#puts](#zard-4b65726e656c2e70757473)"
    assert_equal 1, markdown.scan('<a id="zard-4b65726e656c2e70757473"></a>').length
  end

  def test_custom_labels_can_be_plain_text_or_whole_code_spans
    markdown = render("[Read a value](m:Foo#bar) [`Foo#bar()`](m:Foo#bar) [``bar ` call``](m:Foo#bar)")

    assert_includes markdown, "[Read a value](#zard-466f6f23626172)"
    assert_includes markdown, "[`Foo#bar()`](#zard-466f6f23626172)"
    assert_includes markdown, "[``bar ` call``](#zard-466f6f23626172)"
  end

  def test_custom_labels_escape_markdown_and_decode_bracket_escapes
    markdown = render('[Read \[a value\]](m:Foo#bar) [*literal* _label_](m:Foo#bar)')

    assert_includes markdown, '[Read \[a value\]](#zard-466f6f23626172)'
    assert_includes markdown, '[\*literal\* \_label\_](#zard-466f6f23626172)'
  end

  def test_bracket_operators_accept_bitclust_escaping_and_rd_spacing
    markdown = render('[m:Foo#\[\]] [[m:Foo#[] ]] [`[]`](m:Foo#\[\])')

    assert_equal 2, markdown.scan('[Foo#\[\]](#zard-466f6f235b5d)').length
    assert_includes markdown, "[`[]`](#zard-466f6f235b5d)"
    assert_equal 1, markdown.scan('<a id="zard-466f6f235b5d"></a>').length
  end

  def test_explicit_see_forms_are_processed_before_shorthand
    markdown = render("@see [m:Foo#bar]\n@see [[m:Foo#bar]]\n@see [Read a value](m:Foo#bar)\n@see Read [m:Foo#bar] for details.")

    assert_equal 2, markdown.scan("- [Foo#bar](#zard-466f6f23626172)").length
    assert_includes markdown, "- [Read a value](#zard-466f6f23626172)"
    assert_includes markdown, "- Read [Foo#bar](#zard-466f6f23626172) for details."
  end

  def test_links_all_prose_tag_descriptions_but_leaves_example_content_literal
    markdown = render("@note Read [m:Foo#bar].\n@return Use [[m:Foo#bar]].\n@param value — See [m:Foo#bar].\n@example [m:Foo#bar]")

    assert_includes markdown, "Read [Foo#bar](#zard-466f6f23626172)."
    assert_includes markdown, "Use [Foo#bar](#zard-466f6f23626172)."
    assert_includes markdown, "`value` — See [Foo#bar](#zard-466f6f23626172)."
    assert_includes markdown, "### Examples\n\n[m:Foo#bar]"
  end

  def test_preserves_unresolved_forms_and_wrong_reference_kinds
    prose = "[m:Foo#missing] [[m:Foo#hidden]] [Unknown](m:Foo#undocumented) [c:Foo#bar] [m:Foo] [c:Foo::LIMIT] [lib:Foo]"
    markdown = render(prose)

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_code_spans_are_literal_including_multiline_and_varying_delimiters
    prose = "`[m:Foo#bar]` ``a `[m:Foo#bar]` b``\n`begin\n[m:Foo#bar]\nend`"
    markdown = render("@note #{prose}")

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_examples_alone_do_not_create_reference_anchors
    markdown = render("@example [m:Foo#bar]\n[[m:Foo#bar]]")

    assert_includes markdown, "### Examples\n\n[m:Foo#bar]\n[[m:Foo#bar]]"
    refute_includes markdown, "<a id="
  end

  def test_fenced_and_indented_code_regions_remain_literal
    prose = "~~~ruby\n[m:Foo#bar]\n~~~\n```ruby\n[[m:Foo#bar]]\n```\n    [m:Foo#bar]\n\t[m:Foo#bar]"
    markdown = render("@note #{prose}")

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_indented_paragraph_continuations_do_not_split_inline_code
    prose = "`start\n    [m:Foo#bar]\nfinish [m:Foo#bar]`"
    markdown = render("@note #{prose}")

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_indented_code_after_a_blank_line_is_literal
    markdown = render("@note Text.\n\n    [m:Foo#bar]\n\nThen [m:Foo#bar].")

    assert_includes markdown, "Text.\n\n    [m:Foo#bar]"
    assert_includes markdown, "Then [Foo#bar](#zard-466f6f23626172)."
  end

  def test_prose_outside_a_fenced_container_is_processed
    ["> ```\n> [m:Foo#bar]\nOutside [m:Foo#bar]", "- ```\n  [m:Foo#bar]\nOutside [m:Foo#bar]"].each do |prose|
      markdown = render("@note #{prose}")

      assert_includes markdown, "Outside [Foo#bar](#zard-466f6f23626172)"
    end
  end

  def test_long_fences_and_container_fences_do_not_expose_their_contents
    prose = "````ruby\n```\n[m:Foo#bar]\n````\n> ~~~\n> [m:Foo#bar]\n> ~~~\n- ```\n  [m:Foo#bar]\n  ```"
    markdown = render("@note #{prose}")

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_existing_markdown_links_images_and_reference_links_are_preserved
    prose = "[[m:Foo#bar]](https://example.test) [text [m:Foo#bar]](https://example.test/a(b)) ![m:Foo#bar](image.png) [m:Foo#bar][id]\n[id]: https://example.test/[m:Foo#bar]"
    markdown = render("@note #{prose}")

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_existing_reference_links_do_not_inherit_a_previous_explicit_target
    markdown = render("@note [Read](m:Foo#bar) [Other][id]\n\n[id]: https://example.test")

    assert_includes markdown, "[Read](#zard-466f6f23626172) [Other][id]"
    assert_includes markdown, "[id]: https://example.test"
  end

  def test_multiline_reference_definitions_and_shortcut_links_are_preserved
    prose = "[id]:\n  https://example.test/[m:Foo#bar]\n\n[Read][id]\n\n[m:Foo#bar]\n\n[m:Foo#bar]: https://example.test"
    markdown = render("@note #{prose}")

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_an_unmatched_backtick_run_does_not_expose_another_code_span
    prose = "``unclosed `[m:Foo#bar]`"
    markdown = render("@note #{prose}")

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_unindented_multiline_link_definitions_and_titles_remain_literal
    prose = "[id]:\nhttps://example.test/[m:Foo#bar]\n\"Title [m:Foo#bar]\"\n\n[Read][id]"
    markdown = render("@note #{prose}")

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_quoted_link_titles_and_angle_destinations_remain_literal
    prose = "[Read](https://example.test \"title ) [m:Foo#bar]\") [Other](<https://example.test/)[m:Foo#bar]> 'title ( [m:Foo#bar]')"
    markdown = render(prose)

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_inline_code_cannot_cross_heading_list_or_quote_boundaries
    ["# [m:Foo#bar]", "- [m:Foo#bar]", "> [m:Foo#bar]"].each do |block|
      markdown = render("@note `unclosed\n#{block}\n`")

      assert_includes markdown, block.sub("[m:Foo#bar]", "[Foo#bar](#zard-466f6f23626172)")
    end
    markdown = render("@note # `unclosed\n[m:Foo#bar]`")

    assert_includes markdown, "[Foo#bar](#zard-466f6f23626172)`"
  end

  def test_list_continuation_indentation_distinguishes_prose_and_code
    prose = "- Item\n\n    Read [m:Foo#bar].\n\n      [m:Foo#bar]\n\nOutside [m:Foo#bar]."
    markdown = render("@note #{prose}")

    assert_includes markdown, "    Read [Foo#bar](#zard-466f6f23626172)."
    assert_includes markdown, "      [m:Foo#bar]"
    assert_includes markdown, "Outside [Foo#bar](#zard-466f6f23626172)."
  end

  def test_multiline_reference_definition_titles_remain_literal
    prose = "[id]: https://example.test \"title\n[m:Foo#bar]\"\n\n[Read][id]"
    markdown = render("@note #{prose}")

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_fences_in_list_continuations_preserve_code_and_end_with_the_container
    markdown = render("@note - Item\n\n    ```ruby\n    [m:Foo#bar]")

    assert_includes markdown, "    [m:Foo#bar]"
    refute_includes markdown, "<a id="
    markdown = render("@note - Item\n\n  ```ruby\n  literal\nOutside [m:Foo#bar].")

    assert_includes markdown, "Outside [Foo#bar](#zard-466f6f23626172)."
  end

  def test_leaving_a_nested_list_restores_outer_indentation
    markdown = render("@note - Outer\n  - Inner\n\n  Back to outer.\n\n    Read [m:Foo#bar].")

    assert_includes markdown, "    Read [Foo#bar](#zard-466f6f23626172)."
  end

  def test_inline_code_cannot_cross_a_setext_heading_boundary
    markdown = render("@note `unclosed\nHeading [m:Foo#bar]\n===\n`")

    assert_includes markdown, "Heading [Foo#bar](#zard-466f6f23626172)"
  end

  def test_fenced_contents_do_not_change_the_list_container
    ["```", "~~~"].each do |marker|
      markdown = render("@note - Item\n\n  #{marker}\n  > quote [m:Foo#bar]\n  #{marker}\n\n    Read [m:Foo#bar].")

      assert_includes markdown, "  > quote [m:Foo#bar]"
      assert_includes markdown, "    Read [Foo#bar](#zard-466f6f23626172)."
    end
  end

  def test_reference_definition_titles_respect_backslash_escape_parity
    ["\"", "'", "("].each do |opening|
      closing = (opening == "(") ? ")" : opening
      prose = "[id]: https://example.test #{opening}title\nending" + "\\" * 2 + closing + "\nOutside [m:Foo#bar]."
      markdown = render("@note #{prose}")

      assert_includes markdown, "Outside [Foo#bar](#zard-466f6f23626172)."
      prose = "[id]: https://example.test #{opening}title\nending" + "\\" + closing + "\n[m:Foo#bar]#{closing}\n\nOutside [m:Foo#bar]."
      markdown = render("@note #{prose}")

      assert_includes markdown, "[m:Foo#bar]#{closing}"
      assert_includes markdown, "Outside [Foo#bar](#zard-466f6f23626172)."
    end
  end

  def test_blank_lines_end_inline_code_regions
    markdown = render("@note `begin\n\n[m:Foo#bar]\nend`")

    assert_includes markdown, "`begin\n\n[Foo#bar](#zard-466f6f23626172)\nend`"
  end

  def test_tab_and_list_indented_code_is_preserved
    [" \t[m:Foo#bar]", "-     [m:Foo#bar]", "-\t\t[m:Foo#bar]"].each do |prose|
      markdown = render("@note #{prose}")

      assert_includes markdown, prose
      refute_includes markdown, "<a id="
    end
  end

  def test_comparison_prose_is_not_mistaken_for_html
    markdown = render("Compare x < y and [m:Foo#bar] > z.")

    assert_includes markdown, "Compare x < y and [Foo#bar](#zard-466f6f23626172) > z."
  end

  def test_html_attributes_and_autolinks_are_preserved
    prose = '<a href="/path/[m:Foo#bar]">Link</a> <https://example.test/[m:Foo#bar]> <!-- [m:Foo#bar] -->'
    markdown = render(prose)

    assert_includes markdown, prose
    refute_includes markdown, "<a id="
  end

  def test_labels_with_multiple_code_spans_remain_plain_labels
    markdown = render("[`one` and `two`](m:Foo#bar)")

    assert_includes markdown, '[\`one\` and \`two\`](#zard-466f6f23626172)'
  end

  def test_escaped_markup_and_unclosed_code_spans
    markdown = render('Literal \[m:Foo#bar] and `[m:Foo#bar]')

    assert_includes markdown, 'Literal \[m:Foo#bar] and `[Foo#bar](#zard-466f6f23626172)'
  end

  def test_unclosed_or_unsupported_rd_forms_are_preserved
    ["[[m:Foo#bar]", "[m:Foo#missing", "[[lib:Foo [m:Foo#bar]]]"].each do |prose|
      markdown = render("@note #{prose}")

      assert_includes markdown, prose
      refute_includes markdown, "<a id="
    end
  end

  def test_rendering_does_not_change_descriptions_raw_text_or_spans
    document = parse("@note [m:Foo#bar]\nContinuation [[m:Foo#bar]]")
    before = Marshal.dump(document)

    Zard::Doc.render(document)

    assert_equal before, Marshal.dump(document)
  end

  private

  def render(prose)
    Zard::Doc.render(parse(prose))
  end

  def parse(prose)
    source = +<<~RUBY
      # Container.
      class Foo
        # Constant.
        LIMIT = 1
        # Target.
        def bar = nil
        # Index.
        def [](key) = nil
        # Builder.
        def self.build = nil
        def undocumented = nil
        # Internal.
        private def hidden = nil
      end
      # Helpers.
      module Kernel
        # Writes.
        module_function def puts(value) = nil
      end
    RUBY
    source << prose.lines.map { |line| "# #{line.chomp}\n" }.join
    source << "def call(value = nil) = nil\n"
    Zard.parse(source, path: "example.rb")
  end
end
