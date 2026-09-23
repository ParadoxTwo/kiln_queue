require "rails_helper"

RSpec.describe "Pieces", type: :request do
  let(:member) { create(:member) }

  it "filters the queue by status" do
    create(:piece, title: "Mug", status: "submitted")
    create(:piece, title: "Vase", status: "finished")

    get pieces_path(status: "finished")
    expect(response.body).to include("Vase")
    expect(response.body).not_to include("Mug")
  end

  it "ignores a status that does not exist" do
    get pieces_path(status: "exploded")
    expect(response).to have_http_status(:ok)
  end

  it "takes a piece in" do
    expect {
      post pieces_path, params: { piece: { member_id: member.id, title: "Jug", height_mm: 200, width_mm: 120, depth_mm: 120, clay_body: "Stoneware", glaze_temperature_c: 1240 } }
    }.to change(member.pieces, :count).by(1)
    expect(Piece.last).to be_submitted
  end

  it "rejects a piece with no size" do
    post pieces_path, params: { piece: { member_id: member.id, title: "Jug", height_mm: 0, width_mm: 120, depth_mm: 120, clay_body: "Stoneware", glaze_temperature_c: 1240 } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "does not collect a piece that is still in the queue" do
    piece = create(:piece, :glazed)
    patch collect_piece_path(piece)
    expect(flash[:alert]).to match(/only a finished piece/)
    expect(piece.reload).to be_glazed
  end

  it "collects a finished piece" do
    piece = create(:piece, :finished)
    patch collect_piece_path(piece)
    expect(piece.reload).to be_collected
  end
end
