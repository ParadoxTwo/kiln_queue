class PlacementsController < ApplicationController
  def create
    firing = Firing.find(params[:firing_id])
    piece = Piece.find(params.expect(:piece_id))
    result = Firings::LoadPiece.call(firing:, piece:)

    if result.success?
      redirect_to firing, notice: "#{piece.title} loaded."
    else
      redirect_to firing, alert: result.message
    end
  end
end
