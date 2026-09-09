# src/grapheme_cell_width.cr
require "./grapheme_cell_width/tables"
require "./grapheme_cell_width/grapheme_tables"

# grapheme_cell_width measures the terminal cell width of clean text spans,
# grapheme cluster by grapheme cluster.
#
# Contract: spans are valid UTF-8 text containing no ANSI escape sequences
# and no control characters (C0, DEL, C1). Under that contract `measure`
# performs no validation and never fails. Compile with `-Dgrapheme_cell_width_debug`
# during development to validate the contract and raise on violations.
#
# Segmentation is UAX #29 extended grapheme clusters (Unicode 17.0.0),
# including GB9a/GB9b (spacing marks, prepend) and GB9c (Indic conjuncts:
# "क्‍ष" is one cluster). GB3 (CR × LF) is unreachable under the contract.
#
# Width model (wcwidth-compatible — what most terminals assume):
#   * East Asian Wide/Fullwidth                      -> 2 cells
#   * combining marks (Mn/Me), ZWSP/ZWNJ/ZWJ, word joiner, BOM,
#     Hangul jamo vowels & final consonants, emoji skin-tone modifiers,
#     variation selectors, tag characters             -> 0 cells
#   * an emoji ZWJ sequence (👨‍👩‍👧‍👦), a VS16-widened emoji base (❤️)
#     or a regional-indicator pair (🇺🇸)               -> one 2-cell cluster
#   * everything else                                -> 1 cell
#
# All measurement is allocation-free: spans are read in place and never
# copied, so the same `String`/`Slice` you hand in is what streams out.
module GraphemeCellWidth
  VERSION = "0.5.0"

  extend self

  private WIDTH_EXTPICT_BIT = 0x20_u8
  private WIDTH_VS16_BIT    = 0x40_u8
  private WIDTH_EMOJI_BIT   = 0x80_u8

  private GCB_OTHER   =  0_u8
  private GCB_CR      =  1_u8
  private GCB_LF      =  2_u8
  private GCB_CONTROL =  3_u8
  private GCB_EXTEND  =  4_u8
  private GCB_ZWJ     =  5_u8
  private GCB_RI      =  6_u8
  private GCB_PREPEND =  7_u8
  private GCB_SPACING =  8_u8
  private GCB_L       =  9_u8
  private GCB_V       = 10_u8
  private GCB_T       = 11_u8
  private GCB_LV      = 12_u8
  private GCB_LVT     = 13_u8

  private EXTPICT_BIT = 0x10_u8

  private INCB_NONE      = 0_u8
  private INCB_CONSONANT = 1_u8
  private INCB_LINKER    = 2_u8
  private INCB_EXTEND    = 3_u8
  private INCB_SHIFT     =    5

  def measure(span : String) : Int32
    measure(span.to_slice)
  end

  def measure(bytes : Slice(UInt8)) : Int32
    {% if flag?(:grapheme_cell_width_debug) %}
      validate_contract!(bytes)
    {% end %}

    width      = 0
    i          = 0
    size       = bytes.size
    ptr        = bytes.to_unsafe
    joined     = false
    prev_emoji = false
    prev_zwj   = false

    while i < size
      swar_start = i
      while i + 8 <= size
        word = (ptr + i).as(UInt64*).value
        break if (word & 0x8080_8080_8080_8080_u64) != 0
        width += 8
        i += 8
      end
      if i > swar_start
        joined     = false
        prev_emoji = false
        prev_zwj   = false
        if i < size && ptr[i] == 0xEF_u8 && vs16_follows?(ptr, i, size) &&
           in_ranges?(ptr[i - 1].to_u32, VS16_WIDE)
          width += 1
        end
      end
      break if i >= size

      if ptr[i] < 0x80_u8
        if vs16_follows?(ptr, i + 1, size) && in_ranges?(ptr[i].to_u32, VS16_WIDE)
          width += 2
        else
          width += 1
        end
        prev_emoji = false
        i += 1
        joined   = false
        prev_zwj = false
      else
        cp, len = decode(ptr, i)
        if cp == 0x200D_u32
          joined   = prev_emoji && !prev_zwj
          prev_zwj = true
        else
          entry      = char_width_entry(cp)
          emoji_join = joined && (entry & WIDTH_EXTPICT_BIT) != 0
          zwj_failed = joined && !emoji_join
          joined     = false
          prev_zwj   = false
          unless emoji_join
            w = (entry & 0x3_u8).to_i
            vs16_widened = w == 1 && (entry & WIDTH_VS16_BIT) != 0 &&
                           vs16_follows?(ptr, i + len, size)
            w = 2 if vs16_widened
            width += w
            if w == 0
              if zwj_failed || cp == 0x200B_u32 || cp == 0x2060_u32 || cp == 0xFEFF_u32 ||
                 (0x1160_u32 <= cp <= 0x11FF_u32) || (0xD7B0_u32 <= cp <= 0xD7FF_u32)
                prev_emoji = false
              end
            elsif vs16_widened
              prev_emoji = (entry & WIDTH_EXTPICT_BIT) != 0
            else
              prev_emoji = w == 2 && (entry & WIDTH_EMOJI_BIT) != 0
            end
          end
        end
        i += len
      end
    end
    width
  end

  def width(char : Char) : Int32
    char_width(char.ord.to_u32)
  end

  def each_cluster(span : String, & : Slice(UInt8) ->) : Nil
    each_cluster(span.to_slice) { |cluster| yield cluster }
  end

  def each_cluster(bytes : Slice(UInt8), & : Slice(UInt8) ->) : Nil
    {% if flag?(:grapheme_cell_width_debug) %}
      validate_contract!(bytes)
    {% end %}

    size = bytes.size
    return if size == 0
    ptr = bytes.to_unsafe

    cp, len = decode(ptr, 0)
    prev_gcb, ep, incb = classify(cp)
    ri_count      = prev_gcb == GCB_RI ? 1 : 0
    ext_run       = ep
    zwj_armed     = false
    incb_state    = incb == INCB_CONSONANT ? 1 : 0
    cluster_start = 0
    i             = len

    while i < size
      if prev_gcb == GCB_OTHER && ri_count == 0 && !ext_run && !zwj_armed &&
         incb_state == 0 && ptr[i] < 0x80_u8
        if cluster_start < i
          yield bytes[cluster_start, i - cluster_start]
        end
        run_start = i
        while i + 8 <= size
          word = (ptr + i).as(UInt64*).value
          break if (word & 0x8080_8080_8080_8080_u64) != 0
          i += 8
        end
        while i < size && ptr[i] < 0x80_u8
          i += 1
        end
        run_end = i - 1
        k       = run_start
        while k < run_end
          yield bytes[k, 1]
          k += 1
        end
        cluster_start = run_end
        next
      end

      cp, len = decode(ptr, i)
      gcb, ep, incb = classify(cp)

      if boundary?(prev_gcb, gcb, ep, ri_count, zwj_armed, incb, incb_state)
        yield bytes[cluster_start, i - cluster_start]
        cluster_start = i
        ri_count      = 0
        ext_run       = false
        zwj_armed     = false
        incb_state    = 0
      end

      if gcb == GCB_RI
        ri_count += 1
      else
        ri_count = 0
      end
      if ep
        ext_run   = true
        zwj_armed = false
      elsif gcb == GCB_EXTEND
        zwj_armed = false if zwj_armed
      elsif gcb == GCB_ZWJ && ext_run
        zwj_armed = true
        ext_run   = false
      else
        ext_run   = false
        zwj_armed = false
      end
      case incb
      when INCB_CONSONANT then incb_state = 1
      when INCB_LINKER    then incb_state = 2 if incb_state >= 1
      when INCB_EXTEND
      else incb_state = 0
      end

      prev_gcb = gcb
      i += len
    end

    yield bytes[cluster_start, size - cluster_start] if cluster_start < size
  end

  def measure_each(span : String, & : Slice(UInt8), Int32 ->) : Nil
    each_cluster(span) { |cluster| yield cluster, measure(cluster) }
  end

  def measure_each(bytes : Slice(UInt8), & : Slice(UInt8), Int32 ->) : Nil
    each_cluster(bytes) { |cluster| yield cluster, measure(cluster) }
  end

  def measure_each(spans : Enumerable(String), & : Slice(UInt8), Int32 ->) : Nil
    spans.each do |span|
      measure_each(span) { |cluster, width| yield cluster, width }
    end
  end

  def each(spans : Enumerable(String), & : String, Int32 ->) : Nil
    spans.each { |span| yield span, measure(span) }
  end

  def each(spans : Iterator(String)) : Iterator({String, Int32})
    spans.map { |span| {span, measure(span)} }
  end

  def each(spans : Iterable(String)) : Iterator({String, Int32})
    each(spans.each)
  end

  def each_line(io : IO, & : String, Int32 ->) : Nil
    while line = io.gets(chomp: true)
      yield line, measure(line)
    end
  end

  @[AlwaysInline]
  private def decode(ptr : UInt8*, i : Int32) : {UInt32, Int32}
    b0 = ptr[i].to_u32
    if b0 < 0x80
      {b0, 1}
    elsif b0 < 0xE0
      {((b0 & 0x1F) << 6) |
        (ptr[i + 1].to_u32 & 0x3F), 2}
    elsif b0 < 0xF0
      {((b0 & 0x0F) << 12) |
        ((ptr[i + 1].to_u32 & 0x3F) << 6) |
        (ptr[i + 2].to_u32 & 0x3F), 3}
    else
      {((b0 & 0x07) << 18) |
        ((ptr[i + 1].to_u32 & 0x3F) << 12) |
        ((ptr[i + 2].to_u32 & 0x3F) << 6) |
        (ptr[i + 3].to_u32 & 0x3F), 4}
    end
  end

  @[AlwaysInline]
  private def char_width(cp : UInt32) : Int32
    (char_width_entry(cp) & 0x3_u8).to_i
  end

  @[AlwaysInline]
  private def char_width_entry(cp : UInt32) : UInt8
    return 1_u8 if cp < 0x80
    WIDTH_PAGES.unsafe_fetch(
      (WIDTH_INDEX.unsafe_fetch((cp >> 8).to_i).to_i << 8) + (cp & 0xFF).to_i
    )
  end

  @[AlwaysInline]
  private def vs16_follows?(ptr : UInt8*, i : Int32, size : Int32) : Bool
    i + 3 <= size &&
      ptr[i] == 0xEF_u8 && ptr[i + 1] == 0xB8_u8 && ptr[i + 2] == 0x8F_u8
  end

  private def in_ranges?(cp : UInt32, table : Slice(UInt32)) : Bool
    lo = 0
    hi = (table.size >> 1) - 1
    while lo <= hi
      mid = (lo + hi) >> 1
      if cp < table.unsafe_fetch(mid * 2)
        hi = mid - 1
      elsif cp > table.unsafe_fetch(mid * 2 + 1)
        lo = mid + 1
      else
        return true
      end
    end
    false
  end

  @[AlwaysInline]
  private def boundary?(prev_gcb : UInt8, gcb : UInt8, ep : Bool, ri_count : Int32, zwj_armed : Bool, incb : UInt8, incb_state : Int32) : Bool
    return true if prev_gcb == GCB_OTHER && gcb == GCB_OTHER && !ep && incb != INCB_CONSONANT
    return true if prev_gcb == GCB_CR || prev_gcb == GCB_LF || prev_gcb == GCB_CONTROL
    return true if gcb == GCB_CR || gcb == GCB_LF || gcb == GCB_CONTROL
    return false if prev_gcb == GCB_L && {GCB_L, GCB_V, GCB_LV, GCB_LVT}.includes?(gcb)
    return false if {GCB_LV, GCB_V}.includes?(prev_gcb) && {GCB_V, GCB_T}.includes?(gcb)
    return false if {GCB_LVT, GCB_T}.includes?(prev_gcb) && gcb == GCB_T
    return false if gcb == GCB_EXTEND || gcb == GCB_ZWJ
    return false if gcb == GCB_SPACING
    return false if prev_gcb == GCB_PREPEND
    return false if incb == INCB_CONSONANT && incb_state == 2
    return false if ep && zwj_armed
    return false if gcb == GCB_RI && prev_gcb == GCB_RI && ri_count.odd?
    true
  end

  @[AlwaysInline]
  private def classify(cp : UInt32) : {UInt8, Bool, UInt8}
    return {GCB_OTHER, false, INCB_NONE} if cp < 0x80
    packed = GRAPHEME_PAGES.unsafe_fetch(
      (GRAPHEME_INDEX.unsafe_fetch((cp >> 8).to_i).to_i << 8) + (cp & 0xFF).to_i
    )
    {packed & 0x0F_u8, (packed & EXTPICT_BIT) != 0, (packed >> INCB_SHIFT) & 0x3_u8}
  end

  private def validate_contract!(bytes : Slice(UInt8)) : Nil
    ptr  = bytes.to_unsafe
    i    = 0
    size = bytes.size
    while i < size
      b = ptr[i]
      if b < 0x20_u8 || b == 0x7F_u8
        raise ArgumentError.new "grapheme_cell_width contract violated: control byte 0x#{b.to_s(16, precision: 2, upcase: true)} at offset #{i}"
      elsif b < 0x80_u8
        i += 1
      else
        cp, len = decode(ptr, i)
        if 0x80_u32 <= cp <= 0x9F_u32
          raise ArgumentError.new "grapheme_cell_width contract violated: control character U+#{cp.to_s(16, precision: 4, upcase: true)} at offset #{i}"
        end
        i += len
      end
    end
  end
end
