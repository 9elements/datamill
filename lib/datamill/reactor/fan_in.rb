require 'thread'

module Datamill
  module Reactor

# Manages input from a persistent message queue and implements
# an ephemeral message side-channel. Provides a simple interface
# for consuming messages from both sources, strictly
# prioritizing ephemeral messages over persistent ones.
class FanIn

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

  def with_message
    ensure_started!

    next_message_source.call do |message|
      yield message
    end

    return
  end

  private

  def next_message_source
    @mutex.synchronize do
      loop do
        if @injected_messages.any?
          return method(:handle_ephemeral_message_source)
        elsif @current_persistent_message
          return method(:handle_persistent_message_source)
        else
          @cv.wait(@mutex)
        end
      end
    end
  end

  def handle_ephemeral_message_source
    message =
      @mutex.synchronize do
        @injected_messages.shift
      end

    yield message
  end

  def handle_persistent_message_source
    message =
      @mutex.synchronize do
        msg, @current_persistent_message =
          @current_persistent_message, nil

        msg
      end

    yield message

    @back_channel << nil
  end

  def ensure_started!
    return if @thread

    @mutex.synchronize do
      @thread ||= Thread.new do
        until @ingestion_stopped
          message = @persistent_queue.blocking_peek

          unless @ingestion_stopped
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
