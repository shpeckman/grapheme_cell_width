# spec/grapheme_spec.cr
require "./spec_helper"

private def clusters_of(span : String) : Array(String)
  clusters = [] of String
  GraphemeCellWidth.each_cluster(span) { |c| clusters << String.new(c) }
  clusters
end

describe "GraphemeCellWidth grapheme clusters" do
  describe ".each_cluster" do
    it "segments ASCII into single-character clusters" do
      clusters_of("abc").should eq ["a", "b", "c"]
    end

    it "segments long ASCII runs across the 8-byte fast path" do
      clusters_of("a" * 20).should eq ["a"] * 20
      clusters_of("The quick brown fox").should eq ["T", "h", "e", " ", "q", "u", "i", "c", "k", " ", "b", "r", "o", "w", "n", " ", "f", "o", "x"]
    end

    it "lets the run's final byte join a following combining mark (GB9)" do
      clusters_of("ab\u{301}").should eq ["a", "b\u{301}"]
      clusters_of("hello w\u{301}rld").should eq ["h", "e", "l", "l", "o", " ", "w\u{301}", "r", "l", "d"]
    end

    it "yields no empty clusters around ASCII runs" do
      clusters_of("hello 世界").should eq ["h", "e", "l", "l", "o", " ", "世", "界"]
      clusters_of("abc👋def").should eq ["a", "b", "c", "👋", "d", "e", "f"]
    end

    it "returns nothing for empty spans" do
      clusters_of("").should be_empty
    end

    it "keeps combining marks with their base" do
      clusters_of("éx").should eq ["é", "x"]
      clusters_of("ə̴̥̆!").should eq ["ə̴̥̆", "!"]
    end

    it "keeps ZWJ emoji sequences together" do
      clusters_of("👨‍👩‍👧‍👦").should eq ["👨‍👩‍👧‍👦"]
      clusters_of("a👩‍💻b").should eq ["a", "👩‍💻", "b"]
    end

    it "keeps skin-tone-modified emoji together" do
      clusters_of("👍🏽").should eq ["👍🏽"]
    end

    it "keeps VS16 sequences together" do
      clusters_of("\u{2764}\u{FE0F}").should eq ["\u{2764}\u{FE0F}"]
      clusters_of("1\u{FE0F}\u{20E3}").should eq ["1\u{FE0F}\u{20E3}"]
    end

    it "keeps an ASCII VS16 base in one cluster across the SWAR boundary" do
      clusters_of("Score: 1\u{FE0F}\u{20E3}").should eq ["S", "c", "o", "r", "e", ":", " ", "1\u{FE0F}\u{20E3}"]
    end

    it "pairs regional indicators, breaks between pairs" do
      clusters_of("🇺🇸🇨🇦").should eq ["🇺🇸", "🇨🇦"]
      clusters_of("🇦🇧🇨").should eq ["🇦🇧", "🇨"]
    end

    it "keeps Hangul jamo syllables together" do
      clusters_of("학").should eq ["학"]
      clusters_of("학교").should eq ["학", "교"]
    end

    it "keeps Indic conjuncts together (GB9c)" do
      clusters_of("क्‍ष").should eq ["क्‍ष"]
      clusters_of("क्त").should eq ["क्त"]
      clusters_of("कत").should eq ["क", "त"]
      clusters_of("aक्तb").should eq ["a", "क्त", "b"]
    end

    it "breaks around zero-width format characters" do
      clusters_of("A\u200BB").should eq ["A", "\u200B", "B"]
    end

    it "yields zero-copy views into the span" do
      span  = "日本語"
      bytes = span.to_slice
      GraphemeCellWidth.each_cluster(span) do |cluster|
        offset = cluster.to_unsafe - bytes.to_unsafe
        offset.should be >= 0
        offset.should be < bytes.size
      end
    end
  end

  describe ".measure_each" do
    it "segments and measures one span in a single pass" do
      collected = [] of {String, Int32}
      GraphemeCellWidth.measure_each("a👨‍👩‍👧‍👦日") { |c, w| collected << {String.new(c), w} }
      collected.should eq [{"a", 1}, {"👨‍👩‍👧‍👦", 2}, {"日", 2}]
    end

    it "streams over spans, treating span boundaries as hard breaks" do
      collected = [] of {String, Int32}
      GraphemeCellWidth.measure_each(["👨", "‍👩"]) { |c, w| collected << {String.new(c), w} }
      collected.should eq [{"👨", 2}, {"‍", 0}, {"👩", 2}]
    end
  end

  it "passes the UCD GraphemeBreakTest suite (contract-valid subset)" do
    tests    = 0
    failures = [] of String

    File.each_line("spec/fixtures/GraphemeBreakTest.txt") do |line|
      next unless line.starts_with?('÷')
      tokens = line.split('#', 2)[0].split

      cps           = [] of UInt32
      break_before  = [] of Bool
      pending_break = true
      tokens.each do |token|
        case token
        when "÷" then pending_break = true
        when "×" then pending_break = false
        else
          cps << token.to_u32(16)
          break_before << pending_break
        end
      end

      expected = [] of String
      current  = [] of UInt32
      cps.each_with_index do |cp, k|
        if k > 0 && break_before[k]
          expected << String.build { |io| current.each { |c| io << c.chr } }
          current = [] of UInt32
        end
        current << cp
      end
      expected << String.build { |io| current.each { |c| io << c.chr } } unless current.empty?

      str    = String.build { |io| cps.each { |cp| io << cp.chr } }
      actual = clusters_of(str)

      unless actual == expected
        failures << line
      end

      cluster_total = expected.sum { |cluster| GraphemeCellWidth.measure(cluster) }
      unless GraphemeCellWidth.measure(str) == cluster_total
        failures << "width mismatch (measure != sum of cluster widths): #{line}"
      end

      tests += 1
    end

    if failures.any?
      fail "#{failures.size}/#{tests} GraphemeBreakTest failures, first:\n#{failures.first}"
    end
    tests.should be > 500
  end
end
