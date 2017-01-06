require 'json'

module Datamill

class Event #< Hashie::Mash
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
    end

    def ===(other)
      super || matches_by_format?(other)
    end

    def event_name
      name || raise(ArgumentError)
    end

    def matches_by_format?(raw_message)
      return false unless Hash === raw_message

      raw_message["datamill_event"] == event_name &&
        attributes.all? { |attr_name| raw_message.key?(attr_name) }
    end
  end

  def initialize(value = {})
    if value.key?("datamill_event")
      raise "ArgumentError" unless self.class.matches_by_format?(value)
    end

    @hash = {"datamill_event" => self.class.event_name}.merge(value)
  end

  def to_h
    @hash.clone
  end

  def to_json
    to_h.to_json
  end
end

end
