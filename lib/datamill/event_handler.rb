module Datamill

module EventHandler
  def self.module_for(*event_classes, &handler)
    Module.new do
      define_method(:call) do |message|
        event_class = event_classes.find { |kls| kls === message }
        if event_class
          event = event_class.coerce(message)

          if handler
            handler.call(event)
          else
            handle_event(event)
          end
        end
      end
    end
  end

  def self.for(*event_classes)
    block = Proc.new

    kls = Class.new
    kls.send(:include, module_for(*event_classes, &block))
    kls.new
  end
end

end

