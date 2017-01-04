require 'thread'

module Datamill

# Maintains a thread that allows for a single delayed block
# at a time
class TimerThread
  def initialize
    @mutex = Mutex.new
    @cv = ConditionVariable.new
    @job = nil

    @thread = Thread.new(&method(:thread_body))
  end

  def delayed(delay_seconds, &block)
    @mutex.synchronize do
      @job = Job.new
      @job.block = block
      @job.timeout = [delay_seconds, 0].max

      @cv.signal
    end
    return nil
  end

  private

  Job = Struct.new(:block, :timeout) do
    def call
      block.call
    end
  end

  def thread_body
    loop do
      # We protect against the thread becoming inoperable here.
      # Client code wanting to handle block exceptions must handle these.
      next_due_job.call rescue nil
    end
  end

  def next_due_job
    current_job = nil

    loop do
      timeout = current_job ? current_job.timeout : nil
      if new_job = wait_for_timeout_or_new_job(timeout)
        current_job = new_job
      else
        return current_job
      end
    end
  end

  def wait_for_timeout_or_new_job(timeout)
    @mutex.synchronize do
      @cv.wait(@mutex, timeout) unless @job

      job, @job = @job, nil

      return job
    end
  end
end

end
