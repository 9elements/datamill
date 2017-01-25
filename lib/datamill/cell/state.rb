module Datamill
  module Cell

# Cells are an abstract unit combined of persistent data and a behaviour.
# When behaviour methods are called, a `State` instance is passed.
# Cells communicate with their runtime by altering this state.
#
# Apart from their implementing behaviour, cells are identified by the
# `id` attribute, which is a String.
#
# A cell is terminated when the `persistent_data` attribute of the state
# is `nil` after a behaviour method has been called.
# Only an explicit message from outside will bring it to life then.
# Cells assign persistable data to the `persistent_data` attribute
# to keep their state around and to be kept alive. A living cell has the
# `nop` behaviour method called once during reactor boot.
#
# Cells can request to be called after a timeout by assigning to the
# next_timeout attribute, but only when they have persistent data.
#
# Cells must assign `nil` to `persistent_data` as early as possible
# to free space.
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
