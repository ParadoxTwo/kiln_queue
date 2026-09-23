require "rails_helper"

RSpec.describe Firing do
  it "cannot be planned hotter than its kiln can go" do
    kiln = build(:kiln, max_temperature_c: 1200)
    firing = build(:firing, :glaze, kiln:, target_temperature_c: 1240)

    expect(firing).not_to be_valid
    expect(firing.errors[:target_temperature_c].first).to include("limit of 1200C")
  end

  it "knows how much room is left" do
    firing = create(:firing, kiln: create(:kiln, capacity_cm3: 5_000))
    firing.pieces << create(:piece) # 1,000cm3

    expect(firing.remaining_capacity_cm3).to eq(4_000)
  end
end
