require "rails_helper"

RSpec.describe "Firings", type: :request do
  let(:kiln) { create(:kiln) }

  describe "GET /" do
    it "lists upcoming firings" do
      create(:firing, kiln:, scheduled_on: Date.new(2026, 10, 3))
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2026-10-03")
    end
  end

  describe "POST /firings" do
    it "plans a firing" do
      expect {
        post firings_path, params: { firing: { kiln_id: kiln.id, kind: "glaze", scheduled_on: "2026-10-10", target_temperature_c: 1240 } }
      }.to change(Firing, :count).by(1)
      expect(response).to redirect_to(Firing.last)
    end

    it "re-renders the form when the kiln cannot reach the temperature" do
      post firings_path, params: { firing: { kiln_id: kiln.id, kind: "glaze", scheduled_on: "2026-10-10", target_temperature_c: 1400 } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "loading and firing, end to end" do
    let(:firing) { create(:firing, :glaze, kiln:) }
    let(:piece) { create(:piece, :glazed, title: "Tea bowl") }

    it "loads a piece, fires the kiln, moves the piece on and charges the member" do
      post firing_placements_path(firing, piece_id: piece.id)
      expect(flash[:notice]).to eq("Tea bowl loaded.")

      expect {
        post complete_firing_path(firing)
      }.to change(Charge, :count).by(1)

      expect(piece.reload).to be_finished
      expect(firing.reload).to be_fired
    end

    it "explains why a piece was refused" do
      bisque = create(:firing, kiln:)
      post firing_placements_path(bisque, piece_id: piece.id)
      expect(response).to redirect_to(bisque)
      expect(flash[:alert]).to be_present
      expect(bisque.pieces).to be_empty
    end

    it "will not complete an empty firing" do
      post complete_firing_path(firing)
      expect(flash[:alert]).to be_present
      expect(firing.reload).to be_planned
    end
  end

  describe "GET /firings/:id" do
    it "returns 404 for a firing that does not exist" do
      get firing_path(id: 0)
      expect(response).to have_http_status(:not_found)
    end

    # PINNED DEBT: the show page loads each placement's piece and member one
    # row at a time. This spec records that the query count grows with the
    # load. Whoever fixes it should flip this to "does not grow".
    it "issues more queries as more pieces are loaded (pinned as-is)" do
      firing = create(:firing, :glaze, kiln:)
      create(:placement_for_spec, firing:)
      one = count_queries { get firing_path(firing) }

      4.times { create(:placement_for_spec, firing:) }
      five = count_queries { get firing_path(firing) }

      expect(five).to be > one
    end
  end
end
