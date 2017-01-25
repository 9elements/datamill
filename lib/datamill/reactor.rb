require 'datamill/reactor/instance'

module Datamill

module Reactor
  def self.new(*args)
    Instance.new(*args)
  end
end

end
