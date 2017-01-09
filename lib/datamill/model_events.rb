module Datamill

class ModelEvents < Hash
  def initialize(model)
    @model = model
  end

  def queue_to(queue)
    @queue = queue
  end

  def identify
    @identifier_block = Proc.new
  end

  attr_reader :queue, :model
  attr_reader :identifier_block

  def callbacks
    @callbacks ||= callbacks_class.new(self)
  end

  def publish(record, event_key)
    id = identifier_block.call(record)
    event = fetch(event_key).new
    event.id = id
    queue.push event
  end

  def self.attach_to(model)
    model.send :extend, ModelMethods

    events = model.datamill_model_events = new(model)
    yield events

    events.callbacks.generate_event_cases!
    events.callbacks.hook!
  end

  module ModelMethods
    attr_accessor :datamill_model_events
  end

  class Callbacks
    def initialize(events)
      @events = events
    end
    attr_reader :events

    def model
      events.model
    end

    def build_event_case(name_segment)
      datamill_event_name = "Datamill#{name_segment}"

      Class.new(Datamill::Event) do
        class << self
          attr_reader :event_name
        end
        @event_name = datamill_event_name

        attribute :id
      end
    end
  end

  class TransactionlessCallbacks < Callbacks
    def generate_event_cases!
      events["saved"] = build_event_case("#{model}Saved")
    end

    def hook!
      model.after_save do
        model_events = self.class.datamill_model_events
        model_events.publish(self, "saved")
      end
    end
  end

  private

  def callbacks_class
    if model.respond_to?(:after_commit)
      raise NotImplementedError
    else
      TransactionlessCallbacks
    end
  end
end

end

