module Firings
  # Marks a planned firing as fired and moves every piece in it on a stage.
  # A glaze firing also charges each member for their piece.
  class Complete
    NEXT_STATUS = { "bisque" => "bisqued", "glaze" => "finished" }.freeze

    def self.call(firing, at: Time.current) = new(firing, at:).call

    def initialize(firing, at:)
      @firing = firing
      @at = at
    end

    def call
      return Result.failure(:not_planned, "this firing is already #{@firing.status}") unless @firing.planned?
      return Result.failure(:empty, "there is nothing in this firing") if @firing.pieces.empty?

      Firing.transaction do
        @firing.update!(status: "fired", fired_at: @at)
        @firing.pieces.includes(:member).find_each do |piece|
          piece.update!(status: NEXT_STATUS.fetch(@firing.kind))
          charge!(piece) if @firing.glaze?
        end
      end

      Result.success(@firing)
    end

    private

    def charge!(piece)
      piece.charges.create!(
        member: piece.member,
        amount_cents: Pricing::PieceFee.call(piece),
        description: "Glaze firing #{@firing.scheduled_on.iso8601}: #{piece.title}"
      )
    end
  end
end
