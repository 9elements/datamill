module Datamill::Cell

module Behaviour
  def self.handle_message(state, message)
  end

  def self.handle_timeout(state)
  end

  def self.next_timeout(state)
  end

  def self.behaviour_name
    name
  end
end

end
