require 'datamill/reactor/fan_in'

require 'spec_helper'

describe Datamill::Reactor::FanIn do
  let(:persistent_queue) {
    require 'datamill/persistent_queue/redis'
    instance_double(Datamill::PersistentQueue::Redis)
  }

  subject do
    described_class.new(persistent_queue: persistent_queue)
  end

  let(:message) { double "message" }

  it "delivers a message from the persistent queue" do
    allow(persistent_queue).to receive(:blocking_peek) { message }

    wait_for_condition do |guard|
      expect(persistent_queue).to receive(:seek) {
        guard.notify
      }

      subject.with_message do |msg|
        expect(msg).to be(message)
      end
    end
  end

  context "when a message has been injected" do
    it "delivers it even when the persistent queue is blocking" do
      wait_for_condition do |guard|
        blocked = false
        delivered_message = nil
        guard.add_condition { blocked }
        guard.add_condition { delivered_message }

        allow(persistent_queue).to receive(:blocking_peek) {
          subject.inject_message message
          guard.notify { blocked = true }

          sleep
        }

        subject.with_message do |msg|
          guard.notify { delivered_message = msg }
        end
      end
    end
  end
end

