# spec/joins_spec.cr
require "./spec_helper"

private def boundary_between?(left : String, right : String) : Bool
  joined = left + right
  base   = joined.to_slice.to_unsafe
  found  = false
  GraphemeCellWidth.each_cluster(joined) do |cluster|
    found = true if cluster.to_unsafe - base == left.bytesize
  end
  found
end

describe "GraphemeCellWidth.joins?" do
  it "attaches combining marks and skin-tone modifiers to any base" do
    GraphemeCellWidth.joins?("a", "\u{0301}").should be_true
    GraphemeCellWidth.joins?("a", "\u{1F3FB}").should be_true
    GraphemeCellWidth.joins?(" ", "\u{1F3FB}").should be_true
  end

  it "keeps independent clusters apart" do
    GraphemeCellWidth.joins?("a", "b").should be_false
    GraphemeCellWidth.joins?("中", "文").should be_false
    GraphemeCellWidth.joins?("\u{1F3FB}", " ").should be_false
  end

  it "pairs a lone regional indicator but not a completed flag" do
    GraphemeCellWidth.joins?("\u{1F1EF}", "\u{1F1F5}").should be_true
    GraphemeCellWidth.joins?("\u{1F1EF}", "\u{1F1EF}\u{1F1F5}").should be_true
    GraphemeCellWidth.joins?("\u{1F1EF}\u{1F1F5}", "\u{1F1FA}").should be_false
  end

  it "continues an armed emoji ZWJ sequence" do
    GraphemeCellWidth.joins?("\u{1F468}\u{200D}", "\u{1F469}").should be_true
    GraphemeCellWidth.joins?("\u{1F468}", "\u{1F469}").should be_false
  end

  it "composes Hangul jamo" do
    GraphemeCellWidth.joins?("\u{1100}", "\u{1161}").should be_true
  end

  it "continues an Indic conjunct" do
    GraphemeCellWidth.joins?("क्", "ष").should be_true
    GraphemeCellWidth.joins?("क", "ष").should be_false
  end

  it "attaches whatever follows a prepended character" do
    GraphemeCellWidth.joins?("\u{0600}", "1").should be_true
  end

  it "never joins empty spans" do
    GraphemeCellWidth.joins?("", "a").should be_false
    GraphemeCellWidth.joins?("a", "").should be_false
  end

  it "agrees with the boundary found by segmenting the concatenation" do
    clusters = ["a", " ", "中", "\u{0301}", "\u{1F3FB}", "\u{1F1EF}", "\u{1F1EF}\u{1F1F5}",
                "\u{1F468}\u{200D}", "\u{1F469}", "\u{1100}", "\u{1161}", "क्", "ष", "\u{0600}"]
    clusters.each do |left|
      clusters.each do |right|
        expected = !boundary_between?(left, right)
        GraphemeCellWidth.joins?(left, right).should eq(expected), "#{left.inspect} + #{right.inspect}"
      end
    end
  end
end
