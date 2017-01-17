module Datamill::Cell

module Behaviour
  # This defines the expected interface for a cell behaviour.
  # All methods which take a state argument are callbacks
  # needed to implement behaviour of a living cell.

  def self.nop(state)
  end

  def self.handle_message(state, message)
  end

  def self.handle_timeout(state)
  end

  def self.behaviour_name
    name
  end
end

end
