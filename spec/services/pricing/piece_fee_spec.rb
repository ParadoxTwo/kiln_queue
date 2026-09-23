require "rails_helper"

RSpec.describe Pricing::PieceFee do
  def fee(tier: "standard", **dims)
    Pricing::PieceFee.call(build(:piece, member: build(:member, tier:), **dims))
  end

  it "charges 3 cents per cubic centimetre" do
    expect(fee(height_mm: 200, width_mm: 100, depth_mm: 100)).to eq(6_000) # 2,000cm3
  end

  it "charges the $5 minimum for a small piece" do
    expect(fee(height_mm: 50, width_mm: 50, depth_mm: 50)).to eq(500) # 125cm3 = $3.75
  end

  it "takes 20% off for studio pass members, after the minimum" do
    expect(fee(tier: "studio_pass", height_mm: 50, width_mm: 50, depth_mm: 50)).to eq(400)
  end

  it "rounds to the nearest cent, once, at the end" do
    # 143 x 70 x 100mm = 1,001cm3 -> 3,003c; less 20% = 2,402.4c -> 2,402c
    expect(fee(tier: "studio_pass", height_mm: 143, width_mm: 70, depth_mm: 100)).to eq(2_402)
    # 167 x 60 x 100mm = 1,002cm3 -> 3,006c; less 20% = 2,404.8c -> 2,405c
    expect(fee(tier: "studio_pass", height_mm: 167, width_mm: 60, depth_mm: 100)).to eq(2_405)
  end
end
