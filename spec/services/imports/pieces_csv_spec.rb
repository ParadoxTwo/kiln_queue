require "rails_helper"

# Characterisation spec for legacy code: it pins today's behaviour, including
# the parts that are arguably wrong, so a refactor can't change them by accident.
RSpec.describe Imports::PiecesCsv do
  let(:path) { Rails.root.join("db/sample/saturday_class.csv") }

  before do
    create(:member, name: "Priya Raman", email: "priya@example.com")
    create(:member, name: "Tom Nguyen", email: "tom@example.com")
  end

  it "creates a piece for every usable row and returns the count" do
    expect(described_class.new(path).run).to eq(4)
  end

  it "creates a member it has never seen before" do
    expect { described_class.new(path).run }.to change(Member, :count).by(1)
    expect(Member.find_by(email: "new.student@example.com").name).to eq("Sam Okafor")
  end

  # PINNED: "abc" in width_mm becomes 0 through to_i, the > 0 validation
  # rejects it, and the bare rescue swallows the error. The row simply does not
  # appear, and the only trace is a log line nobody at the front desk reads.
  it "silently drops a row with a non-numeric width (pinned as-is)" do
    expect { described_class.new(path).run }.not_to raise_error
    expect(Piece.where(title: "Ramen bowl")).not_to exist
  end

  # PINNED: nothing identifies a row as already imported.
  it "imports every usable row again when run twice (pinned as-is)" do
    described_class.new(path).run
    expect { described_class.new(path).run }.to change(Piece, :count).by(4)
  end
end
