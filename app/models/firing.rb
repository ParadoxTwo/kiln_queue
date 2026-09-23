class Firing < ApplicationRecord
  KINDS = %w[bisque glaze].freeze
  STATUSES = %w[planned fired cancelled].freeze
  # A glaze firing accepts pieces whose glaze matures within this many degrees
  # of the firing's target. Studio policy, set by the head technician.
  GLAZE_TOLERANCE_C = 10

  belongs_to :kiln
  has_many :placements, dependent: :destroy
  has_many :pieces, through: :placements

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :scheduled_on, presence: true
  validates :target_temperature_c, numericality: { only_integer: true, greater_than: 0 }
  validate :target_within_kiln_limit

  scope :upcoming, -> { where(status: "planned").order(:scheduled_on) }

  def bisque? = kind == "bisque"
  def glaze? = kind == "glaze"
  def planned? = status == "planned"
  def fired? = status == "fired"
  def cancelled? = status == "cancelled"

  # Summed in SQL rather than over the `pieces` association, which Rails
  # caches: a firing object reused across several loads would otherwise keep
  # reporting the volume from the first time it was read. Integer division per
  # row matches Piece#volume_cm3 exactly.
  def loaded_volume_cm3
    pieces.sum(Arel.sql("pieces.height_mm * pieces.width_mm * pieces.depth_mm / 1000"))
  end

  def remaining_capacity_cm3
    kiln.capacity_cm3 - loaded_volume_cm3
  end

  private

  def target_within_kiln_limit
    return if kiln.nil? || target_temperature_c.nil?
    return if target_temperature_c <= kiln.max_temperature_c

    errors.add(:target_temperature_c, "exceeds #{kiln.name}'s limit of #{kiln.max_temperature_c}C")
  end
end
