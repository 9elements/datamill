module Datamill
  module Cell

class State
  def initialize(behaviour:, id:, persistent_data:)
    @behaviour = behaviour
    @id = id
    @persistent_data = persistent_data
  end
  attr_reader :behaviour, :id

  # Cell behaviours can alter this in all cell behaviour callbacks.
  # Updating the backing store happens only after these
  # callbacks finish.
  attr_accessor :persistent_data

  # This is nil anytime a cell behaviour callback is called.
  # Can be set to a duration (in seconds) to demand a handle_timeout
  # message from the reactor.
  attr_accessor :next_timeout
end

  end
end
