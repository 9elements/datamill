module Datamill
  module Cell

class State
  def initialize(behaviour:, id:, persistent_data:)
    @behaviour = behaviour
    @id = id
    @persistent_data = persistent_data
  end
  attr_reader :behaviour, :id
  attr_accessor :persistent_data
end

  end
end
