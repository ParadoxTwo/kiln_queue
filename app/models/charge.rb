class Charge < ApplicationRecord
  belongs_to :member
  belongs_to :piece

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :description, presence: true

  def amount
    Money.format(amount_cents)
  end
end
