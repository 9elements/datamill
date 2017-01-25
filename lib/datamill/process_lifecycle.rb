module Datamill

# Wraps one Datamill process.
module ProcessLifecycle
  def self.new(*attributes)
    result = Class.new(Base) do
      attr_accessor(*attributes)
    end.new
    yield result if block_given?
    result
  end

  class Base
    def setup
      @setup ||= Proc.new
    end

    def teardown
      @teardown ||= Proc.new
    end
  end
end

end

