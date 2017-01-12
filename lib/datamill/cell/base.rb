require 'datamill/cell/reactor_handler'

module Datamill
  module Cell

class Base
  class << self
    def behaviour
      @behaviour ||= Behaviour.new(cell_class: self)
    end

    def queue_to(queue)
      @queue = queue
    end
    attr_reader :queue

    def serialize_id(id)
      unless id.is_a?(String)
        raise ArgumentError,
          "using non-string identifiers requires overwriting serialize_id and unserialize_id class methods"
      end

      id
    end

    def unserialize_id(str)
      str
    end

    def proxy_for(id, proxy_helper: proxy_helper())
      cell_id = serialize_id(id)
      Proxy.new(cell_id, proxy_helper)
    end

    private

    def proxy_helper
      @proxy_helper ||= ProxyHelper.new(behaviour, queue)
    end

    class ProxyHelper
      # abstracts interaction with queue and ReactorHandler away, so that can
      # be stubbed out.

      def initialize(behaviour, queue)
        @behaviour = behaviour
        @queue = queue
      end

      def call(id, packed_method)
        message =
          ReactorHandler.build_message_to_cell(
            behaviour: @behaviour,
            id: id,
            cell_message: packed_method)
        @queue.push message
      end
    end
  end

  class Behaviour
    def initialize(cell_class:)
      @cell_class = cell_class
    end

    def handle_message(cell_state, message)
      Messenger.send_packed_invocation(
        receiver: @cell_class.new(cell_state),
        packed_invocation: message)
    end

    def handle_timeout(cell_state)
      @cell_class.new(cell_state).handle_timeout
    end

    def next_timeout(cell_state)
      @cell_class.new(cell_state).next_timeout
    end

    def behaviour_name
      raise ArgumentError if @cell_class.name.nil?
      "#{@cell_class.name}Behaviour"
    end
  end

  module Messenger
    def self.pack_invocation(method_name:, args:)
      [method_name.to_s, args]
    end

    def self.send_packed_invocation(receiver:, packed_invocation:)
      method_name, args = packed_invocation
      receiver.send(method_name, *args)
    end
  end

  class Proxy
    def initialize(cell_id, proxy_helper)
      @cell_id = cell_id
      @proxy_helper = proxy_helper
    end

    def method_missing(name, *args)
      packed_method = Messenger.pack_invocation(method_name: name, args: args)
      @proxy_helper.call(@cell_id, packed_method)
    end
  end

  def initialize(cell_state)
    @cell_state = cell_state
  end

  def persistent_data
    @cell_state.persistent_data
  end

  def persistent_data=(data)
    @cell_state.persistent_data = data
  end

  def id
    @id ||= self.class.unserialize_id(@cell_state.id)
  end
end

  end
end

