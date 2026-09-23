module Firings
  # Puts a piece into a planned firing, or explains why it can't go in.
  class LoadPiece
    def self.call(firing:, piece:) = new(firing:, piece:).call

    def initialize(firing:, piece:)
      @firing = firing
      @piece = piece
    end

    def call
      failure = check
      return failure if failure

      placement = @firing.placements.create!(piece: @piece)
      Result.success(placement)
    rescue ActiveRecord::RecordNotUnique
      # Two staff members loading the same piece at the same moment: the check
      # below passes for both and the unique index settles it.
      already_loaded
    end

    private

    def check
      return fail(:firing_closed, "this firing is #{@firing.status}, not planned") unless @firing.planned?
      return already_loaded if @firing.placements.exists?(piece_id: @piece.id)
      return fail(:wrong_stage, stage_message) unless right_stage?
      return fail(:temperature_mismatch, temperature_message) unless temperature_ok?
      return fail(:already_booked, "#{@piece.title} is already booked into another planned firing") if booked_elsewhere?
      return fail(:no_room, room_message) if @piece.volume_cm3 > @firing.remaining_capacity_cm3

      nil
    end

    def right_stage?
      @firing.bisque? ? @piece.submitted? : @piece.glazed?
    end

    def temperature_ok?
      return true if @firing.bisque?

      (@piece.glaze_temperature_c - @firing.target_temperature_c).abs <= Firing::GLAZE_TOLERANCE_C
    end

    def booked_elsewhere?
      @piece.placements.joins(:firing)
            .where(firings: { status: "planned" })
            .where.not(firing_id: @firing.id)
            .exists?
    end

    def stage_message
      needed = @firing.bisque? ? "submitted" : "glazed"
      "a #{@firing.kind} firing needs a #{needed} piece; #{@piece.title} is #{@piece.status}"
    end

    def temperature_message
      "#{@piece.title}'s glaze matures at #{@piece.glaze_temperature_c}C; " \
        "this firing goes to #{@firing.target_temperature_c}C"
    end

    def room_message
      "#{@piece.title} needs #{@piece.volume_cm3}cm3; #{@firing.remaining_capacity_cm3}cm3 left"
    end

    def already_loaded = fail(:already_loaded, "#{@piece.title} is already in this firing")

    def fail(code, message) = Result.failure(code, message)
  end
end
