# frozen_string_literal: true

require "test_helper"

class ZardTest < Minitest::Test
  def test_has_a_semantic_version
    assert_match(/\A\d+\.\d+\.\d+\z/, Zard::VERSION)
  end

  def test_exposes_a_library_error
    assert_operator Zard::Error, :<, StandardError
  end
end
