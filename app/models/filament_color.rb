# app/models/filament_color.rb
class FilamentColor < ApplicationRecord
  audited

  validates :name, :code, presence: true
  validates :code, uniqueness: true

  # Optional RGB hex like "#ff9900" or "ff9900" (also accepts short #abc)
  validates :rgb,
            allow_blank: true,
            format: { with: /\A#?(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/,
                      message: "must be a hex color like #ff9900 or #abc" }

  before_validation :normalize_rgb!

  default_scope { order(position: :asc) }
  scope :active, -> { where(active: true) }

  private

  def normalize_rgb!
    return if rgb.blank?
    s = rgb.strip
    s = "##{s}" unless s.starts_with?('#')
    # expand #abc -> #aabbcc
    if s.length == 4
      s = "##{s[1] * 2}#{s[2] * 2}#{s[3] * 2}"
    end
    self.rgb = s.downcase
  end
end
