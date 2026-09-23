# A single ceramic piece a member has handed in for firing.
#
# Lifecycle:
#   submitted --(bisque firing completes)--> bisqued
#   bisqued   --(member glazes it)---------> glazed
#   glazed    --(glaze firing completes)---> finished
#   finished  --(member picks it up)-------> collected
#   any open state --(staff)---------------> damaged
class Piece < ApplicationRecord
  STATUSES = %w[submitted bisqued glazed finished collected damaged].freeze

  belongs_to :member
  has_many :placements, dependent: :restrict_with_error
  has_many :firings, through: :placements
  has_many :charges, dependent: :restrict_with_error

  validates :title, :clay_body, presence: true
  validates :height_mm, :width_mm, :depth_mm,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1_000 }
  validates :glaze_temperature_c, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :with_status, ->(status) { where(status: status) }

  # KNOWN DEBT: a business side effect living in a model callback. It fires on
  # every path that sets status to "finished" - the service, the console, a
  # data fix - which is sometimes what you want and sometimes not. See FUTURE.md.
  after_update_commit :notify_ready_for_collection, if: -> { saved_change_to_status?(to: "finished") }

  STATUSES.each do |name|
    define_method(:"#{name}?") { status == name }
  end

  # Bounding-box volume. Pieces are rarely boxes, but kilns are loaded by the
  # shelf space a piece occupies, and that is a box.
  def volume_cm3
    (height_mm * width_mm * depth_mm) / 1_000
  end

  def mark_glazed!
    raise InvalidTransition, "only a bisqued piece can be glazed (was #{status})" unless bisqued?

    update!(status: "glazed")
  end

  def collect!
    raise InvalidTransition, "only a finished piece can be collected (was #{status})" unless finished?

    update!(status: "collected")
  end

  class InvalidTransition < StandardError; end

  private

  def notify_ready_for_collection
    PieceMailer.ready_for_collection(self).deliver_later
  end
end
