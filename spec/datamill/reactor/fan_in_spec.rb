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
    let(:persistent_queue) do
      # We cannot use rspec-mocks here because blocking in a stubbed method is not possible
      Class.new do
        def blocking_peek
          before_blocking
          sleep
        end
      end.new
    end

    it "delivers it even when the persistent queue is blocking" do
      expect(persistent_queue).to receive(:before_blocking) {
        subject.inject_message message
      }

      delivered_message = nil

      expect {
        subject.with_message do |msg|
          delivered_message = msg
        end
      }.to change { delivered_message }.to(message)
    end
  end
end

