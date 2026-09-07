# tools/dump_widths.cr
require "../src/grapheme_cell_width"

out_path = ARGV[0]? || "widths.tsv"

File.open(out_path, "w") do |file|
  cp = 0x20
  while cp <= 0x10FFFF
    unless 0xD800 <= cp <= 0xDFFF
      file << cp << '\t' << GraphemeCellWidth.width(cp.chr) << '\n'
    end
    cp += 1
  end
end

puts "wrote #{out_path}"