require 'json'

module Datamill

# Convenience class for events that come represented in Hash form for reliable
# (de)serialization. Subclasses can
# * detect events in hash format as matching
# * coerce events in hash format into an `Event` subclass instance
# * be used in `case .. when` for comfortable dispatching of different event cases.
# In the Example, `Event1`, ... are subclasses.
#
#  case event = Event.try_coerce_message(message, event_classes: [Event1, Event2, Event3])
#  when Event1
#    # ... do something
#    event.some_attribute
#  when Event2, Event3
#    # ... do something else
#  end
#
# Attributes are declared using the `attribute` and `attributes` DSL methods:
#
#  Event1 = Class.new(Datamill::Event) do
#    attribute :some_attribute
#  end
#
# New Events are generated and serialized like this:
#
#  event = Event1.new
#  event.some_attribute = "value"
#  event.to_h
class Event
  class << self
    def attributes(*attr_names)
      attr_names.each do |attr_name|
        attribute attr_name
      end

      @attributes ||= []
    end

    def attribute(attr_name)
      attr_name = attr_name.to_s

      define_method(attr_name) do
        @hash.fetch(attr_name)
      end

      define_method("#{attr_name}=") do |value|
        @hash.store(attr_name, value)
      end

      attributes << attr_name
    end

    def ===(other)
      super || matches_by_format?(other)
    end

    def try_coerce_message(message, event_classes: [self])
      if event_class = event_classes.find { |kls| kls === message }
        event_class.coerce(message)
      end
    end

    def coerce(other)
      if other.is_a?(self)
        other
      else
        new(other)
      end
    end

    def event_name
      name || raise(ArgumentError)
    end

    def empty_value
      @empty_value ||=
        attributes.each_with_object({"datamill_event" => event_name}) { |key, acc|
          acc[key] = nil
        }
    end

    def matches_by_format?(raw_message)
      return false unless Hash === raw_message

      raw_message["datamill_event"] == event_name &&
        attributes.all? { |attr_name| raw_message.key?(attr_name) } &&
        raw_message.keys.all? { |key| key == "datamill_event" || attributes.member?(key) }
    end
  end

  def initialize(value = nil)
    if value
      raise ArgumentError unless self.class.matches_by_format?(value)
    else
      value = self.class.empty_value.clone
    end

    @hash = value
  end

  def to_h
    @hash.clone
  end

  def to_json(*args)
    to_h.to_json(*args)
  end

  # Apparently, Rails re-defines the internal recursion for JSON
  # serializatioon to go through as_json instead of to_json...
  def as_json(*args)
    to_h.as_json(*args)
  end

  def ==(other)
    super || (to_h == other)
  end

  def to_s
    "Datamill::Event[ #{self.class.event_name}: #{
      values = @hash.clone
      values.delete "datamill_event"
      values.inspect
    } ]"
  end
end

end
