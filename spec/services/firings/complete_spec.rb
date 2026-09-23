require "rails_helper"

RSpec.describe Firings::Complete do
  let(:at) { Time.zone.parse("2026-10-01 18:00") }

  it "moves every piece in a bisque firing to bisqued without charging" do
    firing = create(:firing)
    firing.pieces << create_list(:piece, 2, :submitted)

    expect { described_class.call(firing, at:) }.not_to change(Charge, :count)
    expect(firing.reload.status).to eq("fired")
    expect(firing.fired_at).to eq(at)
    expect(firing.pieces.map(&:status)).to all(eq("bisqued"))
  end

  it "finishes the pieces in a glaze firing and charges each member" do
    firing = create(:firing, :glaze)
    member = create(:member)
    firing.pieces << create(:piece, :glazed, member:)

    expect { described_class.call(firing, at:) }.to change(member.charges, :count).by(1)
    expect(firing.pieces.first.reload).to be_finished
    expect(member.charges.last.amount_cents).to eq(3_000)
  end

  it "tells each member their piece is ready once the transaction commits" do
    firing = create(:firing, :glaze)
    firing.pieces << create(:piece, :glazed)

    expect { described_class.call(firing, at:) }.to have_enqueued_mail(PieceMailer, :ready_for_collection)
  end

  it "will not complete a firing twice" do
    firing = create(:firing)
    firing.pieces << create(:piece)
    described_class.call(firing, at:)

    result = described_class.call(firing.reload, at:)
    expect(result.code).to eq(:not_planned)
  end

  it "will not complete an empty firing" do
    expect(described_class.call(create(:firing), at:).code).to eq(:empty)
  end
end
