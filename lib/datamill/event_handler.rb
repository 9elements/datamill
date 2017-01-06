module Datamill

class EventHandler
  # Builds a new reactor handler for accepting and
  # handling given event classes.
  # Incoming messages are tested against the given event
  # classes and if they match, converted and passed to
  # the given block.
  def self.for(*event_classes)
    new(event_classes, Proc.new)
  end


  def initialize(event_classes, block)
    @event_classes = event_classes
    @block = block
  end

  def call(message)
    event = @event_classes.find { |kls| kls === message }
    @block.call(event.new(message)) if event
  end
end

end

