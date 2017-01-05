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
    @cv = ConditionVariable.new
    @current_persistent_message = nil
    @injected_messages = []

    @back_channel = Queue.new
  end

  def stop_ingestion!
    @ingestion_stopped = true
    return
  end

  def inject_message(message)
    @mutex.synchronize do
      @injected_messages << message
      @cv.signal
    end
    return
  end

  def until_value
    loop do
      value = yield
      return value if value
    end
  end

  def with_message
    ensure_started!

    kind, raw_message =
      @mutex.synchronize do
        until_value do
          if @injected_messages.any?
            [:ephemeral, @injected_messages.shift]
          elsif @current_persistent_message
            msg = @current_persistent_message
            @current_persistent_message = nil
            [:persistent, msg]
          else
            @cv.wait(@mutex)
            nil
          end
        end
      end

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
        until false
          message = @persistent_queue.blocking_peek

          unless false
            @mutex.synchronize do
              @current_persistent_message = message
              @cv.signal
            end

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
