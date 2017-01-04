require 'spec_helper'

require 'datamill/reactor/instance'

Thread.abort_on_exception = true

describe Datamill::Reactor::Instance do
  let(:message_source) { Queue.new }

  let(:fan_in) do
    Class.new do
      def initialize(message_source)
        @message_source = message_source
      end

      def with_message
        yield @message_source.pop
      end
    end.new(message_source)
  end

  subject {
    described_class.new(persistent_queue: "unused because fan_in is passed", fan_in: fan_in)
  }

  before do
    Thread.new do
      subject.run
    end
  end

  context "with two handlers" do
    let(:handlers) do
      [
        double("handler 1"),
        double("handler 2")
      ]
    end

    before do
      handlers.each do |handler|
        subject.add_handler handler
      end
    end

    context "with one message" do
      let(:message) { double "message" }

      it "calls both handlers with the message" do
        wait_for_condition do |guard|
          seen_handlers = []
          guard.add_condition { seen_handlers.uniq.length == handlers.length }

          handlers.each do |handler|
            expect(handler).to receive(:call).with(message) do
              guard.notify { seen_handlers << handler }
            end
          end

          message_source << message
        end
      end
    end

    context "with two messages" do
      let(:messages) do
        [
          double("first message"),
          double("second message"),
        ]
      end

      it "calls both handlers with the first message, then with the second" do
        wait_for_condition do |guard|
          seen_handlers = []
          guard.add_condition { seen_handlers.uniq.length == handlers.length }

          handlers.each do |handler|
            expect(handler).to receive(:call).with(messages.first) do
              guard.notify { seen_handlers << handler }
            end
          end

          message_source << messages.first
        end

        wait_for_condition do |guard|
          seen_handlers = []
          guard.add_condition { seen_handlers.uniq.length == handlers.length }

          handlers.each do |handler|
            expect(handler).to receive(:call).with(messages.last) do
              guard.notify { seen_handlers << handler }
            end
          end

          message_source << messages.last
        end
      end
    end

    context "with three messages and a faulty handler" do
      let(:messages) do
        [
          double("first message"),
          double("second message"),
          double("third message"),
        ]
      end

      it "calls both handlers with the first message, but not the faulty handler on further messages" do
        faulty_handler, good_handler = *handlers

        wait_for_condition do |guard|
          seen_handlers = []
          guard.add_condition { seen_handlers.uniq.length == handlers.length }

          expect(good_handler).to receive(:call).with(messages.first) do
            guard.notify { seen_handlers << good_handler }
          end

          expect(faulty_handler).to receive(:call).with(messages.first) do
            guard.notify { seen_handlers << faulty_handler }
            raise "an exception"
          end

          message_source << messages.first
        end

        expect(faulty_handler).not_to receive(:call)

        wait_for_condition do |guard|
          received_messages = []
          guard.add_condition { received_messages.uniq.length == 2 }

          allow(good_handler).to receive(:call) do |message|
            guard.notify { received_messages << message }
          end

          messages.each do |message|
            message_source << message
          end
        end
      end
    end
  end
end
