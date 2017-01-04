$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "datamill"

# rspec-mock doubles cannot be used outside of the test
# thread. this function waits for a small timeout until
# an asynchronous condition becomes true, otherwise
# an assertion fails.
# the `guard` that is yielded needs to be notified when
# the condition might have changed. A condition may be absent,
# in which case the assertion succeeds as soon as the guard
# is notified.
def wait_for_condition
  guard = Class.new do
    def initialize(example)
      @example = example
      @conditions = []

      @mutex = Mutex.new
      @cv = ConditionVariable.new
      @fulfilled = false
    end

    def add_condition
      @conditions << Proc.new
      self
    end

    def notify
      yield if block_given?
      if @conditions.all?(&:call)
        @mutex.synchronize do
          @fulfilled = true
          @cv.signal
        end
      end
      self
    end

    def resolve
      yield

      @mutex.synchronize do
        @cv.wait(@mutex, 0.5) unless @fulfilled
      end

      @example.expect(@fulfilled).to @example.be
    end
  end.new(self)

  guard.resolve { yield guard }
end
