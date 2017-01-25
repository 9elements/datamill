require 'datamill/reactor/instance'
require 'datamill/event'

module Datamill

module Reactor
  BootEvent = Class.new(Datamill::Event)

  def self.new(*args)
    Instance.new(*args)
  end
end

end
