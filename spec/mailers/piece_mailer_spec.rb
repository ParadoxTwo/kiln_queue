require "rails_helper"

RSpec.describe PieceMailer do
  describe "#ready_for_collection" do
    let(:member) { create(:member, name: "Priya", email: "priya@example.com") }
    let(:piece) { create(:piece, :finished, member:, title: "Tea bowl") }
    let(:mail) { described_class.ready_for_collection(piece) }

    it "goes to the member who owns the piece" do
      expect(mail.to).to eq([ "priya@example.com" ])
      expect(mail.from).to eq([ "studio@kilnqueue.test" ])
      expect(mail.subject).to eq("Tea bowl is out of the kiln")
    end

    it "tells them where to collect it" do
      expect(mail.body.encoded).to include("Hi Priya", "front desk")
    end
  end
end
