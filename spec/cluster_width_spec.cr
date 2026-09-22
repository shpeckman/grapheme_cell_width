# spec/cluster_width_spec.cr
require "./spec_helper"

private def grapheme(span : String) : Int32
  GraphemeCellWidth.measure(span, GraphemeCellWidth::Mode::Grapheme)
end

private def wcwidth(span : String) : Int32
  GraphemeCellWidth.measure(span, GraphemeCellWidth::Mode::Wcwidth)
end

describe "GraphemeCellWidth grapheme mode" do
  it "agrees with wcwidth on plain text" do
    grapheme("hello").should eq 5
    grapheme("日本語").should eq 6
    grapheme("e\u{301}").should eq 1
    grapheme("학").should eq 2
  end

  it "keeps multi-scalar emoji at two cells" do
    grapheme("👨‍👩‍👧‍👦").should eq 2
    grapheme("👍🏽").should eq 2
    grapheme("🇺🇸").should eq 2
    grapheme("\u{2764}\u{FE0F}").should eq 2
    grapheme("1\u{FE0F}\u{20E3}").should eq 2
  end

  it "narrows an emoji-presentation base followed by VS15" do
    grapheme("\u{231A}").should eq 2
    grapheme("\u{231A}\u{FE0E}").should eq 1
    wcwidth("\u{231A}\u{FE0E}").should eq 2
  end

  it "measures a lone skin-tone modifier as two cells" do
    grapheme("\u{1F3FB}").should eq 2
    wcwidth("\u{1F3FB}").should eq 0
  end

  it "does not widen a letter carrying a skin-tone modifier" do
    grapheme("a\u{1F3FB}").should eq 1
  end

  it "measures an Indic conjunct as its widest scalar" do
    grapheme("क्ष").should eq 1
    wcwidth("क्ष").should eq 2
  end

  it "measures spans as the sum of their cluster widths" do
    grapheme("a\u{231A}\u{FE0E}b").should eq 3
    grapheme("क्षx").should eq 2
  end

  it "streams cluster widths from measure_each" do
    collected = [] of {String, Int32}
    GraphemeCellWidth.measure_each("क्षx\u{1F3FB}", GraphemeCellWidth::Mode::Grapheme) do |cluster, width|
      collected << {String.new(cluster), width}
    end
    collected.should eq [{"क्ष", 1}, {"x\u{1F3FB}", 1}]
  end

  it "exposes cluster_width for a single cluster" do
    GraphemeCellWidth.cluster_width("\u{1F3FB}").should eq 2
    GraphemeCellWidth.cluster_width("").should eq 0
  end

  it "leaves wcwidth measurement unchanged" do
    ["क्ष", "\u{231A}\u{FE0E}", "\u{1F3FB}", "Hello, 世界! 👋"].each do |span|
      wcwidth(span).should eq GraphemeCellWidth.measure(span)
    end
  end
end
