# spec/contract_debug_spec.cr
require "./spec_helper"

{% if flag?(:grapheme_cell_width_debug) %}
  describe "grapheme_cell_width contract validation (-Dgrapheme_cell_width_debug)" do
    it "raises on C0 control bytes" do
      expect_raises(ArgumentError, /control byte/) { GraphemeCellWidth.measure("a\tb") }
      expect_raises(ArgumentError, /control byte/) { GraphemeCellWidth.measure("line\n") }
    end

    it "raises on DEL" do
      expect_raises(ArgumentError, /control byte/) { GraphemeCellWidth.measure("a\u{7F}b") }
    end

    it "raises on C1 control characters" do
      expect_raises(ArgumentError, /control character/) { GraphemeCellWidth.measure("a\u{85}b") }
    end

    it "raises on control bytes in each_cluster" do
      expect_raises(ArgumentError, /control byte/) { GraphemeCellWidth.each_cluster("a\tb") { } }
    end

    it "accepts clean text" do
      GraphemeCellWidth.measure("Hello, 世界! 👋").should eq 15
    end
  end
{% end %}