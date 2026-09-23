class Kiln < ApplicationRecord
  has_many :firings, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :capacity_cm3, numericality: { only_integer: true, greater_than: 0 }
  validates :max_temperature_c, numericality: { only_integer: true, greater_than: 0 }
end
