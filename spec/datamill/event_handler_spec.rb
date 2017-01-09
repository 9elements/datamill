require 'datamill/event_handler'
require 'datamill/event'

describe Datamill::EventHandler do
  let(:event_class) do
    Class.new(Datamill::Event) do
      def self.event_name
        "event name"
      end
    end
  end

  let(:event) do
    event_class.new
  end

  context "with a handler class" do
    let(:handler_class) do
      event_kls = event_class

      Class.new do
        def handle_event(event)
        end

        include Datamill::EventHandler.module_for(event_kls)
      end
    end

    it "dispatches a matching event to #handle_event" do
      handler = handler_class.new
      expect(handler).to receive(:handle_event).with(event)

      handler.call(event)
    end
  end

  context "with an ad-hoc handler block" do
    let(:proxied) { double "proxied" }
    let(:handler) do
      described_class.for(event_class) { |event| proxied.call(event) }
    end

    it "dispatches a matching event to the block" do
      expect(proxied).to receive(:call).with(event)
      handler.call(event)
    end

    it "does not dispatch a non-matching object" do
      expect(proxied).not_to receive(:call)
      handler.call(5)
    end

    it "dispatches a matching event equivalent (hash) to the block coerced as an event" do
      expect(proxied).to receive(:call) { |evt|
        expect(evt).to be_a(event_class)
        expect(evt.to_h).to be == event.to_h
      }
      handler.call(event.to_h)
    end
  end
end
