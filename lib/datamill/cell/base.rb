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
end

  end
end

