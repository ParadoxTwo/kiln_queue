# Demo data. Safe to run repeatedly: bin/rails db:seed
electric = Kiln.find_or_create_by!(name: "Big Electric") { |k| k.capacity_cm3 = 60_000; k.max_temperature_c = 1300 }
small = Kiln.find_or_create_by!(name: "Test Kiln") { |k| k.capacity_cm3 = 8_000; k.max_temperature_c = 1250 }

members = {
  priya: Member.find_or_create_by!(email: "priya@example.com") { |m| m.name = "Priya Raman"; m.tier = "studio_pass" },
  tom: Member.find_or_create_by!(email: "tom@example.com") { |m| m.name = "Tom Nguyen" },
  ines: Member.find_or_create_by!(email: "ines@example.com") { |m| m.name = "Ines Delacroix" }
}

if Piece.none?
  [
    [ :priya, "Moon jar", 300, 280, 280, "Porcelain", 1260, "glazed" ],
    [ :priya, "Espresso cups (set of 4)", 70, 180, 180, "Stoneware", 1240, "submitted" ],
    [ :tom, "Serving platter", 45, 380, 300, "Stoneware", 1240, "glazed" ],
    [ :tom, "Planter", 200, 220, 220, "Terracotta", 1060, "submitted" ],
    [ :ines, "Carved lamp base", 350, 180, 180, "Stoneware", 1240, "bisqued" ],
    [ :ines, "Tiny spirit animal", 50, 40, 60, "Stoneware", 1240, "finished" ]
  ].each do |who, title, h, w, d, clay, temp, status|
    Piece.create!(member: members[who], title:, height_mm: h, width_mm: w, depth_mm: d,
                  clay_body: clay, glaze_temperature_c: temp, status:)
  end
end

Firing.find_or_create_by!(kiln: electric, kind: "glaze", scheduled_on: Date.current + 3) { |f| f.target_temperature_c = 1240 }
Firing.find_or_create_by!(kiln: small, kind: "bisque", scheduled_on: Date.current + 1) { |f| f.target_temperature_c = 1000 }

puts "Seeded #{Kiln.count} kilns, #{Member.count} members, #{Piece.count} pieces, #{Firing.count} firings."
