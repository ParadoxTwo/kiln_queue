module Pricing
  # The glaze-firing fee for one piece, in cents.
  #
  #   rate:      3 cents per cm3 of bounding-box volume
  #   minimum:   $5.00 per piece
  #   discount:  studio pass members get 20% off, applied after the minimum
  #   rounding:  half up, to the cent, once, at the end
  class PieceFee
    RATE_CENTS_PER_CM3 = BigDecimal("3")
    MINIMUM_CENTS = 500
    STUDIO_PASS_DISCOUNT = BigDecimal("0.20")

    def self.call(piece) = new(piece).call

    def initialize(piece)
      @piece = piece
    end

    def call
      base = [ RATE_CENTS_PER_CM3 * @piece.volume_cm3, BigDecimal(MINIMUM_CENTS) ].max
      base *= (1 - STUDIO_PASS_DISCOUNT) if @piece.member.studio_pass?
      base.round(0, BigDecimal::ROUND_HALF_UP).to_i
    end
  end
end
