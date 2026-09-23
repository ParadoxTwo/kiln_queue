class FiringsController < ApplicationController
  def index
    @upcoming = Firing.upcoming.includes(:kiln)
    @recent = Firing.where(status: "fired").includes(:kiln).order(fired_at: :desc).limit(10)
  end

  def show
    @firing = Firing.find(params[:id])
    # KNOWN DEBT: the view walks placement -> piece -> member one row at a
    # time. Fine at ten pieces, not at a full kiln. See FUTURE.md.
    @placements = @firing.placements
    @candidates = candidates_for(@firing)
  end

  def new
    @firing = Firing.new(scheduled_on: Date.current + 7, kind: "bisque")
  end

  def create
    @firing = Firing.new(firing_params)
    if @firing.save
      redirect_to @firing, notice: "Firing planned for #{@firing.scheduled_on}."
    else
      render :new, status: :unprocessable_content
    end
  end

  def complete
    firing = Firing.find(params[:id])
    result = Firings::Complete.call(firing)
    if result.success?
      redirect_to firing, notice: "Firing complete. Pieces have moved on."
    else
      redirect_to firing, alert: result.message
    end
  end

  private

  def candidates_for(firing)
    return Piece.none unless firing.planned?

    Piece.includes(:member).with_status(firing.bisque? ? "submitted" : "glazed").order(:created_at)
  end

  def firing_params
    params.expect(firing: %i[kiln_id kind scheduled_on target_temperature_c])
  end
end
