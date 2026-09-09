# spec/grapheme_cell_width_spec.cr
require "./spec_helper"

private def each_range(table : Slice(UInt32), & : UInt32, UInt32 ->)
  i = 0
  while i < table.size
    yield table[i], table[i + 1]
    i += 2
  end
end

private def in_table?(cp : UInt32, table : Slice(UInt32)) : Bool
  lo = 0
  hi = (table.size >> 1) - 1
  while lo <= hi
    mid = (lo + hi) >> 1
    if cp < table[mid * 2]
      hi = mid - 1
    elsif cp > table[mid * 2 + 1]
      lo = mid + 1
    else
      return true
    end
  end
  false
end

private def surrogate?(cp : UInt32) : Bool
  0xD800_u32 <= cp <= 0xDFFF_u32
end

describe GraphemeCellWidth do
  describe ".measure" do
    it "measures empty spans" do
      GraphemeCellWidth.measure("").should eq 0
    end

    it "measures ASCII" do
      GraphemeCellWidth.measure("hello").should eq 5
      GraphemeCellWidth.measure("a" * 100).should eq 100
    end

    it "measures ASCII runs crossing the 8-byte fast path" do
      GraphemeCellWidth.measure("aaaaaaa" + "é" + "b" * 20).should eq 28
      GraphemeCellWidth.measure("1234567" + "日" + "12345678").should eq 17
    end

    it "measures Latin-1 and combining marks" do
      GraphemeCellWidth.measure("héllo").should eq 5
      GraphemeCellWidth.measure("e\u{301}").should eq 1
      GraphemeCellWidth.measure("é").should eq 1
    end

    it "measures CJK as 2 cells" do
      GraphemeCellWidth.measure("日本語").should eq 6
      GraphemeCellWidth.measure("한국어").should eq 6
      GraphemeCellWidth.measure("中文测试").should eq 8
    end

    it "measures fullwidth forms as 2 cells" do
      GraphemeCellWidth.measure("Ｆｏｏ").should eq 6
    end

    it "measures conjoining Hangul jamo as one 2-cell syllable" do
      GraphemeCellWidth.measure("학").should eq 2
    end

    it "measures zero-width format characters as 0" do
      GraphemeCellWidth.measure("A\u{200B}B").should eq 2
      GraphemeCellWidth.measure("\u{FEFF}x").should eq 1
      GraphemeCellWidth.measure("x\u{AD}").should eq 2
    end

    it "measures emoji with Emoji_Presentation as 2 cells" do
      GraphemeCellWidth.measure("👋").should eq 2
      GraphemeCellWidth.measure("🎉🎉").should eq 4
    end

    it "measures ZWJ sequences as one glyph" do
      GraphemeCellWidth.measure("👨‍👩‍👧‍👦").should eq 2
      GraphemeCellWidth.measure("👩‍💻").should eq 2
    end

    it "does not let a ZWJ swallow a non-emoji scalar" do
      GraphemeCellWidth.measure("👋‍é").should eq 3
      GraphemeCellWidth.measure("👩‍本").should eq 4
      GraphemeCellWidth.measure("👋‍❤️").should eq 2
    end

    it "resets emoji-join state across the 8-byte ASCII fast path" do
      GraphemeCellWidth.measure("👋aaaaaaaa‍👩").should eq 12
      GraphemeCellWidth.measure("👋‍aaaaaaaa本").should eq 12
      GraphemeCellWidth.measure("👋aaaaaaa‍👩").should eq 11
    end

    it "measures skin-tone-modified emoji as one glyph" do
      GraphemeCellWidth.measure("👍🏽").should eq 2
    end

    it "measures regional indicator pairs (flags) as 2 cells" do
      GraphemeCellWidth.measure("🇺🇸").should eq 2
    end

    it "measures narrow emoji bases with VS16 as 2 cells" do
      GraphemeCellWidth.measure("\u{2764}").should eq 1
      GraphemeCellWidth.measure("\u{2764}\u{FE0F}").should eq 2
      GraphemeCellWidth.measure("\u{2708}\u{FE0F}").should eq 2
      GraphemeCellWidth.measure("1\u{FE0F}\u{20E3}").should eq 2
      GraphemeCellWidth.measure("Score: 1\u{FE0F}\u{20E3}").should eq 9
      GraphemeCellWidth.measure("1234567" + "1\u{FE0F}\u{20E3}").should eq 9
      GraphemeCellWidth.measure("rank 3\u{FE0F} and 7\u{FE0F}").should eq 14
    end

    it "measures mixed spans" do
      GraphemeCellWidth.measure("Hello, 世界! 👋").should eq 15
    end

    it "measures raw byte slices without copying" do
      GraphemeCellWidth.measure("日本語".to_slice).should eq 6
    end
  end

  describe ".width" do
    it "measures single scalars" do
      GraphemeCellWidth.width('a').should eq 1
      GraphemeCellWidth.width('日').should eq 2
      GraphemeCellWidth.width('\u{301}').should eq 0
      GraphemeCellWidth.width('❤').should eq 1
    end
  end

  describe ".each" do
    it "streams spans with widths (block form)" do
      collected = [] of {String, Int32}
      GraphemeCellWidth.each(["foo", "日本語", "héllo"]) { |span, w| collected << {span, w} }
      collected.should eq [{"foo", 3}, {"日本語", 6}, {"héllo", 5}]
    end

    it "streams lazily as an iterator" do
      iter = GraphemeCellWidth.each(["ab", "日"])
      iter.to_a.should eq [{"ab", 2}, {"日", 2}]
    end

    it "wraps an existing span iterator" do
      GraphemeCellWidth.each(["x", "yz"].each).to_a.should eq [{"x", 1}, {"yz", 2}]
    end

    it "never copies spans" do
      span = "original"
      GraphemeCellWidth.each([span]) { |s, _| s.same?(span).should be_true }
    end
  end

  describe ".each_line" do
    it "streams lines from an IO" do
      io        = IO::Memory.new("foo\n日本語\n")
      collected = [] of {String, Int32}
      GraphemeCellWidth.each_line(io) { |line, w| collected << {line, w} }
      collected.should eq [{"foo", 3}, {"日本語", 6}]
    end
  end

  describe "generated tables" do
    it "has zero width at every ZERO range boundary" do
      each_range(GraphemeCellWidth::ZERO) do |first, last|
        next if first <= 0xDFFF_u32 && last >= 0xD800_u32
        GraphemeCellWidth.width(first.chr).should eq 0
        GraphemeCellWidth.width(last.chr).should eq 0
      end
    end

    it "has width 2 at every WIDE range boundary" do
      each_range(GraphemeCellWidth::WIDE) do |first, last|
        GraphemeCellWidth.width(first.chr).should eq 2
        GraphemeCellWidth.width(last.chr).should eq 2
      end
    end

    it "is narrow in the gaps between WIDE ranges" do
      prev_last : UInt32? = nil
      each_range(GraphemeCellWidth::WIDE) do |first, last|
        if prev = prev_last
          gap = prev + 1
          if gap < first && !surrogate?(gap) && !in_table?(gap, GraphemeCellWidth::ZERO)
            GraphemeCellWidth.width(gap.chr).should eq 1
          end
        end
        prev_last = last
      end
    end

    it "keeps ZERO and WIDE disjoint and sorted" do
      each_range(GraphemeCellWidth::WIDE) do |first, last|
        in_table?(first, GraphemeCellWidth::ZERO).should be_false
        in_table?(last, GraphemeCellWidth::ZERO).should be_false
      end
      [GraphemeCellWidth::ZERO, GraphemeCellWidth::WIDE, GraphemeCellWidth::VS16_WIDE].each do |table|
        each_range(table) do |first, last|
          first.should be <= last
        end
        i = 2
        while i < table.size
          table[i].should be > table[i - 1]
          i += 2
        end
      end
    end

    it "widens every VS16 base before U+FE0F, and only then" do
      each_range(GraphemeCellWidth::VS16_WIDE) do |first, last|
        GraphemeCellWidth.measure(first.chr.to_s).should eq 1
        GraphemeCellWidth.measure(first.chr.to_s + "\u{FE0F}").should eq 2
        GraphemeCellWidth.measure(last.chr.to_s + "\u{FE0F}").should eq 2
      end
    end

    it "keeps the flat width table consistent with the range tables for every scalar" do
      cp = 0x20_u32
      while cp <= 0x10FFFF_u32
        unless surrogate?(cp)
          expected = if in_table?(cp, GraphemeCellWidth::ZERO)
                       0
                     elsif in_table?(cp, GraphemeCellWidth::WIDE)
                       2
                     else
                       1
                     end
          GraphemeCellWidth.width(cp.chr).should eq expected
        end
        cp &+= 1
      end
    end
  end
end
