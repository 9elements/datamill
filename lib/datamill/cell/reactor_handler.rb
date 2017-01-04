require 'datamill/cell/state'

module Datamill::Cell

class ReactorHandler
  class << self
    def build_message_to_cell(behaviour:, id:, cell_message:)
      build_handler_message(
        TO_CELL,
        "behaviour" => behaviour.behaviour_name,
        "cell_id" => id,
        "cell_message" => cell_message
      )
    end

    def build_launch_message
      build_handler_message(LAUNCH)
    end

    # used internally
    def build_handler_message(msg, payload = nil)
      {
        "target" => AS_MESSAGE_TARGET,
        "msg" => msg,
        "payload" => payload
      }
    end
  end

  def initialize(persistent_hash:, behaviour_registry:, delayed_message_emitter:)
    @persistent_hash = persistent_hash
    @behaviour_registry = behaviour_registry
    @delayed_message_emitter = delayed_message_emitter

    @timeouts = {}
  end

  def call(handler_message)
    return if ignore_handler_message?(handler_message)

    dispatch_handler_message(handler_message)

    if next_timeout = @timeouts.values.first
      delay = [next_timeout - Time.now, 0].max
      message = self.class.build_handler_message(TIMER)
      @delayed_message_emitter.call(delay, message)
    end
  end

  private

  def ignore_handler_message?(message)
    !(
      message.respond_to?(:key?) &&
      message.fetch("target", false) == AS_MESSAGE_TARGET
    )
  end

  def dispatch_handler_message(message)
    case message.fetch("msg")
    when TO_CELL
      handle_handler_message_to_cell(message)
    when TIMER
      handle_handler_message_timer
    when LAUNCH
      handle_handler_message_launch
    else
      raise ArgumentError
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
    payload = handler_message.fetch("payload")

    behaviour_name = payload.fetch("behaviour")
    cell_id = payload.fetch("cell_id")
    cell_message = payload.fetch("cell_message")

    key = cell_key(behaviour_name, cell_id)
    state = cell_state(key)

    operating_cell(key, state) do
      state.behaviour.handle_message(state, cell_message)
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

  AS_MESSAGE_TARGET = "CellHandler"
  LAUNCH = "Launch"
  TIMER = "Timer"
  TO_CELL = "ToCell"

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

