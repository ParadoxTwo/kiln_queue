class PieceMailer < ApplicationMailer
  def ready_for_collection(piece)
    @piece = piece
    mail to: piece.member.email, subject: "#{piece.title} is out of the kiln"
  end
end
