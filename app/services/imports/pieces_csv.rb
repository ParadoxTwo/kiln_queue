require "csv"

# LEGACY: used after each Saturday class, when the teacher hands the front
# desk a spreadsheet of everything the class made. Returns how many pieces it
# created. See FUTURE.md.
#
# Expected headers: email, name, title, height_mm, width_mm, depth_mm, clay_body, glaze_temperature_c
module Imports
  class PiecesCsv
    def initialize(path)
      @path = path
    end

    def run
      created = 0
      CSV.foreach(@path, headers: true) do |row|
        begin
          member = Member.find_by(email: row["email"].to_s.strip.downcase)
          if member.nil?
            member = Member.create!(name: row["name"], email: row["email"])
          end
          Piece.create!(
            member: member,
            title: row["title"],
            height_mm: row["height_mm"].to_i,
            width_mm: row["width_mm"].to_i,
            depth_mm: row["depth_mm"].to_i,
            clay_body: row["clay_body"],
            glaze_temperature_c: row["glaze_temperature_c"].to_i
          )
          created += 1
        rescue => e
          Rails.logger.warn("import: skipped a row: #{e.message}")
          next
        end
      end
      created
    end
  end
end
