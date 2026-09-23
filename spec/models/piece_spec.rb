require "rails_helper"

RSpec.describe Piece do
  describe "#volume_cm3" do
    it "is the bounding box in cubic centimetres" do
      expect(build(:piece, height_mm: 200, width_mm: 150, depth_mm: 100).volume_cm3).to eq(3_000)
    end

    it "truncates rather than rounds a part cubic centimetre" do
      expect(build(:piece, height_mm: 11, width_mm: 11, depth_mm: 11).volume_cm3).to eq(1)
    end
  end

  describe "validations" do
    it "requires positive whole-millimetre dimensions" do
      expect(build(:piece, height_mm: 0)).not_to be_valid
      expect(build(:piece, width_mm: 12.5)).not_to be_valid
    end

    it "rejects a status outside the lifecycle" do
      expect(build(:piece, status: "lost")).not_to be_valid
    end
  end

  describe "#mark_glazed!" do
    it "moves a bisqued piece to glazed" do
      piece = create(:piece, :bisqued)
      piece.mark_glazed!
      expect(piece.reload).to be_glazed
    end

    it "refuses a piece that has not been bisque fired" do
      piece = create(:piece, :submitted)
      expect { piece.mark_glazed! }.to raise_error(Piece::InvalidTransition, /only a bisqued piece/)
    end
  end

  describe "#collect!" do
    it "refuses a piece that is still waiting for its glaze firing" do
      expect { create(:piece, :glazed).collect! }.to raise_error(Piece::InvalidTransition)
    end
  end

  describe "ready-for-collection email" do
    it "is sent when a piece becomes finished" do
      piece = create(:piece, :glazed)
      expect { piece.update!(status: "finished") }
        .to have_enqueued_mail(PieceMailer, :ready_for_collection)
    end

    it "is not sent for other changes" do
      piece = create(:piece, :finished)
      expect { piece.update!(title: "Renamed") }.not_to have_enqueued_mail(PieceMailer, :ready_for_collection)
    end
  end
end
