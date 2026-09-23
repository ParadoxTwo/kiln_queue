require "rails_helper"

RSpec.describe "Reports", type: :request do
  let(:member) { create(:member, name: "Priya") }

  it "renders a plain-text statement for the month" do
    travel_to Time.zone.local(2026, 9, 15) do
      create(:charge, member:, amount_cents: 2_402)
    end

    get monthly_statement_path(member_id: member.id, month: "2026-09")

    expect(response.media_type).to eq("text/plain")
    expect(response.body).to include("Priya", "September 2026", "TOTAL: $24.02")
  end

  it "answers 400 for a month it cannot read" do
    get monthly_statement_path(member_id: member.id, month: "september")
    expect(response).to have_http_status(:bad_request)
  end

  it "answers 404 for a member who does not exist" do
    get monthly_statement_path(member_id: 0)
    expect(response).to have_http_status(:not_found)
  end
end
