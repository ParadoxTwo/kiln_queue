FactoryBot.define do
  factory :member do
    sequence(:name) { |n| "Member #{n}" }
    sequence(:email) { |n| "member#{n}@example.com" }
    tier { "standard" }

    trait(:studio_pass) { tier { "studio_pass" } }
  end

  factory :kiln do
    sequence(:name) { |n| "Kiln #{n}" }
    capacity_cm3 { 50_000 }
    max_temperature_c { 1300 }
  end

  factory :piece do
    member
    sequence(:title) { |n| "Piece #{n}" }
    # 100 x 100 x 100mm = 1,000cm3
    height_mm { 100 }
    width_mm { 100 }
    depth_mm { 100 }
    clay_body { "Stoneware" }
    glaze_temperature_c { 1240 }
    status { "submitted" }

    Piece::STATUSES.each { |s| trait(s.to_sym) { status { s } } }
  end

  factory :firing do
    kiln
    kind { "bisque" }
    scheduled_on { Date.new(2026, 10, 1) }
    target_temperature_c { 1000 }
    status { "planned" }

    trait(:glaze) do
      kind { "glaze" }
      target_temperature_c { 1240 }
    end
  end

  factory :charge do
    member
    piece { association :piece, member: member }
    amount_cents { 1_500 }
    description { "Glaze firing" }
  end

  # A placement whose piece is at the right stage for its firing.
  factory :placement_for_spec, class: "Placement" do
    firing
    piece { association :piece, status: firing.glaze? ? "glazed" : "submitted" }
  end
end
