require "rails_helper"

RSpec.describe Firings::LoadPiece do
  let(:kiln) { create(:kiln, capacity_cm3: 2_500) }
  let(:bisque) { create(:firing, kiln:) }
  let(:glaze) { create(:firing, :glaze, kiln:) }

  def load(firing, piece) = described_class.call(firing:, piece:)

  it "loads a submitted piece into a bisque firing" do
    result = load(bisque, create(:piece, :submitted))

    expect(result).to be_success
    expect(bisque.pieces.count).to eq(1)
  end

  it "loads a glazed piece into a glaze firing at a matching temperature" do
    expect(load(glaze, create(:piece, :glazed, glaze_temperature_c: 1250))).to be_success
  end

  it "refuses a firing that is no longer planned" do
    bisque.update!(status: "fired")
    expect(load(bisque, create(:piece)).code).to eq(:firing_closed)
  end

  it "refuses a piece at the wrong stage for the firing" do
    expect(load(bisque, create(:piece, :glazed)).code).to eq(:wrong_stage)
    expect(load(glaze, create(:piece, :submitted)).code).to eq(:wrong_stage)
  end

  it "refuses a glaze that matures more than 10C away from the target" do
    result = load(glaze, create(:piece, :glazed, glaze_temperature_c: 1260))

    expect(result.code).to eq(:temperature_mismatch)
    expect(result.message).to include("1260C", "1240C")
  end

  it "refuses a piece already booked into another planned firing" do
    piece = create(:piece)
    load(create(:firing, kiln:), piece)

    expect(load(bisque, piece).code).to eq(:already_booked)
  end

  it "refuses a piece that will not fit in the space left" do
    load(bisque, create(:piece)) # 1,000
    load(bisque, create(:piece)) # 2,000 of 2,500

    result = load(bisque, create(:piece))
    expect(result.code).to eq(:no_room)
    expect(result.message).to include("500cm3 left")
  end

  it "refuses to load the same piece twice" do
    piece = create(:piece)
    load(bisque, piece)

    expect(load(bisque, piece).code).to eq(:already_loaded)
    expect(bisque.pieces.count).to eq(1)
  end
end
