require 'datamill/cell/state'
require 'datamill/event'

module Datamill
  module Reactor

# A `Reactor` handler managing cells. Register an instance of it with the Reactor.
#
# Reactor handlers are simple stateless managers of incoming messages. Cells are stateful
# object-like managers of events with a lifetime. This class bridges these concepts
# by managing cell invocations.
class CellHandler
  module Event
    Timeout = Class.new(Datamill::Event)
    MessageToCell = Class.new(Datamill::Event) do
      attributes :behaviour_name, :id, :cell_message
    end
  end

  class << self
    def build_message_to_cell(behaviour:, id:, cell_message:)
      result = Event::MessageToCell.new
      result.behaviour_name = behaviour.behaviour_name
      result.id = id
      result.cell_message = cell_message
      result
    end
  end

  def initialize(persistent_hash:, delayed_message_emitter:)
    @persistent_hash = persistent_hash
    @delayed_message_emitter = delayed_message_emitter

    @behaviours_by_name = {}
    @timeouts = {}
  end

  def register_behaviour(named_behaviour)
    @behaviours_by_name[named_behaviour.behaviour_name] = named_behaviour
    self
  end

  def call(message)
    event =
      Datamill::Event.try_coerce_message(
        message,
        event_classes: [Reactor::BootEvent, Event::Timeout, Event::MessageToCell])

    if event
      case event
      when Reactor::BootEvent
        handle_handler_message_launch
      when Event::Timeout
        handle_handler_message_timer
      when Event::MessageToCell
        handle_handler_message_to_cell(event)
      end

      if next_timeout = @timeouts.values.sort.first
        delay = [next_timeout - Time.now, 0].max
        @delayed_message_emitter.call(delay, Event::Timeout.new)
      end
    end
  end

  private

  def handle_handler_message_launch
    @persistent_hash.keys.each do |key|
      state = cell_state(key)

      operating_cell(key, state) do
        state.behaviour.nop(state)
      end
    end
  end

  def handle_handler_message_timer
    now = Time.now

    @timeouts.each_pair do |key, time|
      next if time > now

      state = cell_state(key)
      operating_cell(key, state) do
        state.behaviour.handle_timeout(state)
      end
    end
  end

  def handle_handler_message_to_cell(handler_message)
    key = cell_key(handler_message.behaviour_name, handler_message.id)
    state = cell_state(key)

    operating_cell(key, state) do
      state.behaviour.handle_message(state, handler_message.cell_message)
    end
  end

  private

  module NullBehaviour
    def self.nop(state)
    end

    def self.handle_message(state, message)
      state.persistent_data = nil
    end

    def self.handle_timeout(state)
      state.persistent_data = nil
    end
  end

  def operating_cell(key, state)
    persistent_data = state.persistent_data

    yield

    if !state.persistent_data.equal?(persistent_data)
      if state.persistent_data.nil?
        @persistent_hash.delete key
      else
        @persistent_hash[key] = state.persistent_data
      end
    end

    unless state.persistent_data.nil?
      if next_timeout = state.next_timeout
        @timeouts[key] = next_timeout
      else
        @timeouts.delete key
      end
    end

  rescue
    # exception in behaviour, disable cell

    @timeouts.delete key
    @persistent_hash.delete key
  end

  def cell_state(key)
    behaviour, id = cell_key_to_behaviour_and_id(key)
    value = @persistent_hash[key]

    Datamill::Cell::State.new(
      id: id,
      behaviour: behaviour,
      persistent_data: value,
    )
  end

  def cell_key(behaviour, cell_id)
    "#{behaviour}-#{cell_id}"
  end

  def cell_key_to_behaviour_and_id(key)
    behaviour_name, id = key.split('-', 2)
    behaviour = @behaviours_by_name[behaviour_name] || NullBehaviour

    [behaviour, id]
  end
end

  end
end

