# A small result object so services can report an expected failure without
# raising. `Result.success(value)` / `Result.failure(code, message)`.
class Result
  attr_reader :value, :code, :message

  def self.success(value = nil) = new(true, value, nil, nil)
  def self.failure(code, message) = new(false, nil, code, message)

  def initialize(ok, value, code, message)
    @ok, @value, @code, @message = ok, value, code, message
    freeze
  end

  def success? = @ok
  def failure? = !@ok
end
