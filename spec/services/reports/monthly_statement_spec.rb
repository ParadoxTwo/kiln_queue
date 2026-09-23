require "rails_helper"

# Characterisation spec for legacy code: it pins what the statement prints
# today, so it can be refactored safely.
RSpec.describe Reports::MonthlyStatement do
  let(:member) { create(:member, name: "Priya Raman", email: "priya@example.com") }

  before do
    travel_to(Time.zone.parse("2026-09-10 10:00")) do
      create(:charge, member:, piece: create(:piece, member:, title: "Tea bowl"), amount_cents: 1_250)
      create(:charge, member:, piece: create(:piece, member:, title: "Moon jar"), amount_cents: 70_560)
    end
    travel_to(Time.zone.parse("2026-08-31 10:00")) do
      create(:charge, member:, piece: create(:piece, member:, title: "Last month"), amount_cents: 999)
    end
  end

  it "prints the member's charges for the month and a total" do
    expect(described_class.new(member.id, Date.new(2026, 9, 1)).to_s).to eq(<<~TEXT)
      KILN QUEUE - MONTHLY STATEMENT
      Member: Priya Raman (priya@example.com)
      Month: September 2026

      Tea bowl                          1000cm3  $12.50
      Moon jar                          1000cm3  $705.60

      TOTAL: $718.10
    TEXT
  end

  it "mentions the discount for studio pass members" do
    member.update!(tier: "studio_pass")
    expect(described_class.new(member.id, Date.new(2026, 9, 1)).to_s).to end_with("Studio pass discount applied.\n")
  end

  it "prints no thousands separator, unlike the rest of the app (pinned as-is)" do
    create(:charge, member:, piece: create(:piece, member:, title: "Big"), amount_cents: 123_456)
    expect(described_class.new(member.id, Date.current).to_s).to include("$1234.56")
  end
end
