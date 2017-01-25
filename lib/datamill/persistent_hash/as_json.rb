require 'json'

module Datamill
  module PersistentHash

# Decorator class for (de)serialization values via JSON format
class AsJson

  def self.decorate(hash)
    new(hash)
  end

  def initialize(decorated)
    @decorated = decorated
  end

  def keys
    @decorated.keys
  end

  def [](key)
    raw = @decorated[key]

    if raw.nil?
      nil
    else
      JSON.parse(raw).first
    end
  end

  def []=(key, value)
    raw = [value].to_json

    raise ArgumentError unless value == JSON.parse(raw).first
    @decorated[key] = raw
  end

  def delete(key)
    @decorated.delete(key)
  end
end

  end
end
