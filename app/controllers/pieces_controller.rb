class PiecesController < ApplicationController
  before_action :set_piece, only: %i[show mark_glazed collect]

  def index
    @status = params[:status].presence_in(Piece::STATUSES)
    @pieces = Piece.includes(:member).order(created_at: :desc)
    @pieces = @pieces.with_status(@status) if @status
  end

  def show; end

  def new
    @piece = Piece.new
  end

  def create
    @piece = Piece.new(piece_params)
    if @piece.save
      redirect_to @piece, notice: "#{@piece.title} is in the queue."
    else
      render :new, status: :unprocessable_content
    end
  end

  def mark_glazed
    transition { @piece.mark_glazed! }
  end

  def collect
    transition { @piece.collect! }
  end

  private

  def set_piece
    @piece = Piece.find(params[:id])
  end

  def transition
    yield
    redirect_to @piece, notice: "#{@piece.title} is now #{@piece.status}."
  rescue Piece::InvalidTransition => e
    redirect_to @piece, alert: e.message
  end

  def piece_params
    params.expect(piece: %i[member_id title height_mm width_mm depth_mm clay_body glaze_temperature_c])
  end
end
