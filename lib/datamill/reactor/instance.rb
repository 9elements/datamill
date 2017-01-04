require 'datamill/reactor/fan_in'

module Datamill::Reactor

class Instance
  def initialize(persistent_queue:, fan_in: FanIn.new(persistent_queue: persistent_queue))
    @fan_in = fan_in
    @handlers = []
    @running = true
    @injected_messages = []
  end

  def add_handler(handler)
    @handlers << handler
  end

  def stop_ingestion!
    @fan_in.stop_ingestion!
  end

  def inject_message(message)
    @fan_in.inject_message message
  end

  def run
    loop do
      @fan_in.with_message do |msg|
        # Handlers raising an exception do not break the loop,
        # but are excempt from further iterations.
        # Handlers need to provide their own failure handling if needd.

        failed_handlers = []

        @handlers.each do |handler|
          begin
            handler.call(msg)
          rescue
            failed_handlers << handler
          end
        end

        failed_handlers.each do |handler|
          @handlers.delete(handler)
        end
      end
    end
  end
end

end
