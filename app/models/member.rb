class Member < ApplicationRecord
  TIERS = %w[standard studio_pass].freeze

  has_many :pieces, dependent: :restrict_with_error
  has_many :charges, dependent: :restrict_with_error

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :tier, inclusion: { in: TIERS }

  def studio_pass?
    tier == "studio_pass"
  end
end
