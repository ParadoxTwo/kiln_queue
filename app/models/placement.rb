class Placement < ApplicationRecord
  belongs_to :firing
  belongs_to :piece

  validates :piece_id, uniqueness: { scope: :firing_id }
end
