module Datamill::Cell

class BehaviourRegistry
  def initialize
    @behaviours = {}
  end

  def []=(behaviour_name, behaviour)
    @behaviours[behaviour_name.to_s] = behaviour
    behaviour
  end

  def [](behaviour_name)
    @behaviours.fetch(behaviour_name.to_s, nil)
  end

  def register(named_behaviour)
    self[named_behaviour.behaviour_name] = named_behaviour
    self
  end
end

end

