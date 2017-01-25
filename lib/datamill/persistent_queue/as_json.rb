require 'json'

module Datamill
  module PersistentQueue

# Decorator class for (de)serialization via JSON format
class AsJson

  def self.decorate(queue)
    new(queue)
  end

  def initialize(decorated)
    @decorated = decorated
  end

  def push(item)
    raw = [item].to_json

    raise ArgumentError unless item == JSON.parse(raw).first
    @decorated.push(raw)
  end

  def blocking_peek
    JSON.parse(@decorated.blocking_peek).first
  end

  def seek
    @decorated.seek
  end
end

  end
end

