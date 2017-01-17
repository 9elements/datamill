module Datamill::Cell

module Behaviour
  # This defines the expected interface for a cell behaviour.

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
