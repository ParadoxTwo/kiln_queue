# LEGACY: written in an afternoon when the studio first started charging, and
# it has worked well enough that nobody has touched it since. The front desk
# prints one per member at the end of each month. See FUTURE.md.
module Reports
  class MonthlyStatement
    def initialize(member_id, month)
      @member_id = member_id
      @month = month
    end

    def to_s
      member = Member.find(@member_id)
      out = ""
      out += "KILN QUEUE - MONTHLY STATEMENT\n"
      out += "Member: " + member.name + " (" + member.email + ")\n"
      out += "Month: " + @month.strftime("%B %Y") + "\n"
      out += "\n"

      total = 0.0
      start_of_month = @month.beginning_of_month
      end_of_month = @month.end_of_month
      Charge.where(member_id: @member_id).order(:created_at).each do |charge|
        if charge.created_at.to_date >= start_of_month && charge.created_at.to_date <= end_of_month
          piece = Piece.find(charge.piece_id)
          dollars = charge.amount_cents / 100.0
          total = total + dollars
          out += piece.title.ljust(30) + "  " + piece.volume_cm3.to_s.rjust(6) + "cm3  $" + format("%.2f", dollars) + "\n"
        end
      end

      out += "\n"
      out += "TOTAL: $" + format("%.2f", total) + "\n"
      if member.tier == "studio_pass"
        out += "Studio pass discount applied.\n"
      end
      out
    end
  end
end
