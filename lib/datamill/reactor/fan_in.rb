require 'thread'

module Datamill
  module Reactor

class FanIn
  # Handles input from persistent queue and
  # ephemeral input channel and provides
  # a simple interface for consuming messages

  def initialize(persistent_queue:)
    @persistent_queue = persistent_queue

    @ingestion_stopped = false
    @mutex = Mutex.new
    @queue = Queue.new
    @back_channel = Queue.new
  end

  def stop_ingestion!
    @ingestion_stopped = true
    return
  end

  def inject_message(message)
    @queue << [:ephemeral, message]
    return
  end

  def with_message
    ensure_started!

    kind, raw_message = @queue.pop

    case kind
    when :ephemeral
      yield raw_message
    when :persistent
      yield raw_message
      @back_channel << nil
    else
      raise ArgumentError
    end

    return
  end

  private

  def ensure_started!
    return if @thread

    @mutex.synchronize do
      @thread ||= Thread.new do
        until @ingestion_stopped
          message = @persistent_queue.blocking_peek

          unless @ingestion_stopped
            @queue << [:persistent, message]

            @back_channel.pop
            @persistent_queue.seek
          end
        end
      end
    end
  end
end

  end
end
