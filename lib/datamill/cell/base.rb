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

    # Adds a middleware to the stack for this cell class.
    # Middlewares wrap around cell method invocations when the cell is being
    # operated upon, that is, when it is being invoked from its behaviour.
    # Invocations from _inside_ such a method are not affected.
    #
    # Middlewares are intended for things like exception tracing and
    # presenting a cell's compound persistent state in a nicer way.
    #
    # A middleware is a callable expecting four _regular_ parameters,
    # * the cell instance
    # * the name of the method the invocation wraps, as a STRING
    # * an array of arguments being passed to the method
    # * a callable (without args) to recurse down the middleware stack.
    #
    # Alternatively, a symbol can be passed. In this case, the
    # corresponding cell instance method will be passed with the same
    # arguments except:
    # * the cell instance is dropped (it is already the receiver of the middleware method)
    # * the recursion callable is passed as a block argument
    #
    # When implementing your middleware, make sure to pass on return values.
    #
    # Midlewares are added in the order from the bottom (close to the reactor)
    # to the top (close to the invoked method) of the stack.
    def add_middleware(middleware)
      middleware_callables <<
        case middleware
        when Symbol
          ->(cell, method_name, args, callable) { cell.send(middleware, method_name, args, &callable) }
        else
          middleware
        end
    end

    def middleware_callables
      @middleware_callables ||= []
    end

    def unserialize_cell_id_to(*attribute_names)
      @cell_id_converter = CellIdConverter.new(attribute_names, Proc.new)
    end

    def identify_cell(*args)
      unless args.length == 1 && args.first.is_a?(String)
        raise ArgumentError, "You are calling .proxy_for with not exactly one string.
          In this case, you need to implement conversion between proxy_for arguments
          and a cell id (a String) by using the unserialize_cell_id_to DSL method
          and overiding the .identify_cell class method."
      end

      args.first
    end

    def proxy_for(*args, proxy_helper: proxy_helper())
      cell_id = identify_cell(*args)
      proxy_for_cell_id(cell_id, proxy_helper: proxy_helper)
    end

    def proxy_for_cell_id(cell_id, proxy_helper: proxy_helper())
      Proxy.new(cell_id, proxy_helper)
    end

    def new(*)
      finalize
      super
    end

    private

    def finalize
      @finalized ||= true.tap do
        unless @cell_id_converter
          # default implementation is to have an id attribute which is just the cell id
          unserialize_cell_id_to(:id) do |cell_id|
            { id: cell_id }
          end
        end

        include @cell_id_converter.attribute_methods
      end
    end

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
        packed_invocation: message
      )
    end

    def handle_timeout(cell_state)
      receiver = @cell_class.new(cell_state)

      receiver.send_with_middlewares("handle_timeout")
    end

    def next_timeout(cell_state)
      receiver = @cell_class.new(cell_state)
      receiver.send_with_middlewares("next_timeout")
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

      receiver.send_with_middlewares(method_name, *args)
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

  class CellIdConverter
    def initialize(attribute_names, attribute_filler)
      @attribute_names = attribute_names
      @attribute_filler = attribute_filler
    end

    def attribute_methods
      attribute_names = @attribute_names
      attribute_filler = @attribute_filler

      Module.new do
        attribute_names.each do |name|
          define_method(name) do
            cell_id_attributes_hash.fetch(name) {
              cell_id_attributes_hash.fetch(name.to_s)
            }
          end
        end

        private define_method(:cell_id_attributes_hash) {
          @cell_id_attributes_hash ||= attribute_filler.call(cell_id)
        }
      end
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

  def cell_id
    @cell_state.id
  end

  def next_timeout=(timeout)
    @cell_state.next_timeout = timeout
  end

  def send_with_middlewares(method_name, *args)
    send_with_explicit_middlewares(
      self.class.middleware_callables.clone, method_name, *args)
  end

  private

  def send_with_explicit_middlewares(middlewares, method_name, *args)
    if middleware = middlewares.shift
      block = ->{ send_with_explicit_middlewares(middlewares, method_name, *args) }
      middleware.call(self, method_name, args, block)
    else
      send(method_name, *args)
    end
  end
end

  end
end

