require 'redis'

module Datamill::PersistentQueue

class Redis
  DEFAULT_KEY = self.name

  # Single consumer, muliple producer
  # reliable queue. Consumer must acknowledge
  # processing of item with seek, otherwise
  # a blocking_peek will produce the same
  # item again.
  #
  # This implementation uses Redis.

  def initialize(connection_factory: ::Redis.method(:new), base_key: DEFAULT_KEY)
    @connection_factory = connection_factory
    @producer_connection = connection_factory.call
    @waiting_queue = base_key
    @current_item_key = "#{base_key}-current"

    # Since there is only one consumer, cache the current value here.
    @current = nil
  end

  def push(item)
    @producer_connection.lpush(@waiting_queue, item.to_s)
    return
  end

  def blocking_peek
    @current ||= consumer_connection.lpop(@current_item_key) || blocking_read
  end

  def seek
    raise ArgumentError unless @current

    consumer_connection.lpop(@current_item_key)
    @current = nil
  end

  private

  def blocking_read
    no_timeout = 0
    consumer_connection.brpoplpush(@waiting_queue, @current_item_key, no_timeout)
  end

  def consumer_connection
    @consumer_connection ||= @connection_factory.call
  end
end

end

