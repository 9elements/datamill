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

  context "when both an injected message and messages on the persistent queue are available" do
    let(:injected_message) { double "injected message" }
    let(:regular_message) { double "regular message" }

    let(:regular_message_factories) do
      [
        -> { regular_message },
        -> { regular_message },
        -> { sleep }
      ]
    end

    before do
      allow(persistent_queue).to receive(:blocking_peek) {
        regular_message_factories.first.call
      }

      allow(persistent_queue).to receive(:seek) {
        regular_message_factories.shift
      }
    end

    it "prioritizes injected messages over those from the persistent queue at #with_message time" do
      # ensure the internal thread is spawned, i.e. let the
      # implementation assume a steady-state
      wait_for_condition do |guard|
        received = nil
        guard.add_condition { received }
        subject.with_message do |message|
          guard.notify do
            received = message
          end
        end
      end

      wait_for_condition do |guard|
        # we wait a tiny bit for the second regular message to be peeked
        sleep 0.1
        guard.notify do
          subject.inject_message injected_message
        end
      end

      received_message = nil
      expect {
        subject.with_message do |message|
          received_message = message
        end
      }.to change { received_message }.to(injected_message)
    end

  end
end

