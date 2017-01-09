require 'datamill/cell/state'
require 'datamill/event_handler'
require 'datamill/event'

module Datamill
  module Cell

class ReactorHandler
  module Event
    Launch = Class.new(Datamill::Event)
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

    def build_launch_message
      Event::Launch.new
    end
  end

  def initialize(persistent_hash:, behaviour_registry:, delayed_message_emitter:)
    @persistent_hash = persistent_hash
    @behaviour_registry = behaviour_registry
    @delayed_message_emitter = delayed_message_emitter

    @timeouts = {}
  end

  include EventHandler.module_for(Event::Launch, Event::Timeout, Event::MessageToCell)

  private

  def handle_event(event)
    case event
    when Event::Launch
      handle_handler_message_launch
    when Event::Timeout
      handle_handler_message_timer
    when Event::MessageToCell
      handle_handler_message_to_cell(event)
    end

    if next_timeout = @timeouts.values.first
      delay = [next_timeout - Time.now, 0].max
      @delayed_message_emitter.call(delay, Event::Timeout.new)
    end
  end

  def handle_handler_message_launch
    @persistent_hash.keys.each do |key|
      state = cell_state(key)

      operating_cell(key, state) do
        # do not call the cell behaviour,
        # just let operating_cell handle the timeout bookkeeping
      end
    end
  end

  def handle_handler_message_timer
    now = Time.now

    @persistent_hash.keys.each do |key|
      state = cell_state(key)
      operating_cell(key, state, only_if_due_at: now) do
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
    def self.handle_message(state, message)
      state.persistent_data = nil
    end

    def self.handle_timeout(state)
      state.persistent_data = nil
    end

    def self.next_timeout(state)
      nil
    end
  end

  def operating_cell(key, state, only_if_due_at: nil)
    if !only_if_due_at || due_at?(state, only_if_due_at)
      persistent_data = state.persistent_data

      yield state

      if !state.persistent_data.equal?(persistent_data)
        if state.persistent_data.nil?
          @persistent_hash.delete key
        else
          @persistent_hash[key] = state.persistent_data
        end
      end

      unless state.persistent_data.nil?
        if next_timeout = state.behaviour.next_timeout(state)
          @timeouts[key] = next_timeout
        else
          @timeouts.delete key
        end
      end
    end

  rescue
    # exception in behaviour, disable cell

    @timeouts.delete key
    @persistent_hash.delete key
  end

  def due_at?(state, time)
    next_timeout = state.behaviour.next_timeout(state)

    next_timeout && next_timeout <= time
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
    behaviour = @behaviour_registry[behaviour_name] || NullBehaviour

    [behaviour, id]
  end
end

  end
end

