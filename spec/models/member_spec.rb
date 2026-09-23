require "rails_helper"

RSpec.describe Member do
  it "normalises email so the same person cannot sign up twice with different casing" do
    create(:member, email: "Priya@Example.com ")
    duplicate = build(:member, email: "priya@example.com")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to include("has already been taken")
  end

  it "rejects an unknown tier" do
    expect(build(:member, tier: "gold")).not_to be_valid
  end
end
