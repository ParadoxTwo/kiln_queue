# Money is integer cents everywhere. This is the one place it becomes text.
module Money
  module_function

  def format(cents)
    sign = cents.negative? ? "-" : ""
    dollars, rem = cents.abs.divmod(100)
    "#{sign}$#{dollars.to_s.reverse.scan(/\d{1,3}/).join(',').reverse}.#{rem.to_s.rjust(2, '0')}"
  end
end
