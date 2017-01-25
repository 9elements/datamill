require 'redis'

module Datamill::PersistentHash

# A persistent hash map with string keys and values.
# Absent values are returned as nil.
#
# This implementation uses Redis.
class Redis

  def initialize(connection: ::Redis.new, base_key:)
    @connection = connection
    @base_key = base_key
  end

  def keys
    @connection.hkeys(@base_key)
  end

  def [](key)
    @connection.hget(@base_key, key)
  end

  def []=(key, value)
    @connection.hset(@base_key, key, value.to_s)
    return nil
  end

  def delete(key)
    @connection.hdel(@base_key, key)
    return nil
  end
end

end
