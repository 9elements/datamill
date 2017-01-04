require 'datamill/cell/reactor_handler'
require 'datamill/cell/behaviour_registry'
require 'datamill/cell/behaviour'

describe Datamill::Cell::ReactorHandler do
  let(:persistent_hash) { {} }
  let(:delayed_message_emitter) { double "delayed message emitter" }

  let(:behaviours) { [] }
  let(:behaviour_registry) do
    Datamill::Cell::BehaviourRegistry.new.tap do |registry|
      behaviours.each { |behaviour| registry.register(behaviour) }
    end
  end

  def self.declare_behaviour(name)
    let(name) do
      instance_double(
        Datamill::Cell::Behaviour.singleton_class,
        {
          behaviour_name: name.to_s,
          next_timeout: nil
        }
      )
    end

    before do
      behaviours << send(name)
    end
  end

  subject {
    described_class.new(
      persistent_hash: persistent_hash,
      behaviour_registry: behaviour_registry,
      delayed_message_emitter: delayed_message_emitter
    )
  }

  def expect_to_cause_one_delayed_message
    delayed_message = nil

    expect(delayed_message_emitter).to receive(:call) do |_delay, message|
      delayed_message = message
    end

    yield

    return delayed_message
  end

  def expect_not_to_cause_a_delayed_message
    expect(delayed_message_emitter).not_to receive(:call)

    yield

    return
  end

  describe "launching" do
    context "without persistent data" do
      it "does nothing upon launch" do
        subject.call(described_class.build_launch_message)
      end
    end

    context "with persistent data" do
      declare_behaviour(:behaviour)

      let(:cell_id) { "cell id" }
      let(:initial_data) { double("initial data") }

      before do
        # here, we make an assumption about internals!
        persistent_key = "#{behaviour.behaviour_name}-#{cell_id}"
        persistent_hash[persistent_key] = initial_data
      end

      context "when cell signals a timeout is necessary" do
        it "uses timer to perform timeout message delivery" do
          next_timeout = nil
          allow(behaviour).to receive(:next_timeout) { |_|
            next_timeout
          }

          emitted_message =
            expect_to_cause_one_delayed_message do
              next_timeout = Time.now
              subject.call(described_class.build_launch_message)
            end

          next_timeout = Time.now
          expect(behaviour).to receive(:handle_timeout) do
            next_timeout = nil
          end
          subject.call(emitted_message)
        end
      end
    end
  end

  describe "sending a cell message" do
    context "for a nonexistent behaviour" do
      before do
        subject.call(described_class.build_launch_message)
      end

      let(:unregistered_behaviour) do
        double(:unregistered_behaviour, behaviour_name: "unregistered")
      end

      let(:cell_id) { "cell id" }
      let(:cell_message) { "cell message" }
      let(:handler_message) {
        described_class.build_message_to_cell(
          behaviour: unregistered_behaviour,
          id: cell_id,
          cell_message: cell_message)
      }

      it "is ignored" do
        subject.call(handler_message)
      end
    end

    context "for an existing behaviour" do
      declare_behaviour(:behaviour)

      let(:cell_id) { "cell id" }
      let(:cell_message) { "cell message" }
      let(:handler_message) {
        described_class.build_message_to_cell(
          behaviour: behaviour,
          id: cell_id,
          cell_message: cell_message)
      }

      context "when cell crashes in handle_message" do
        before do
          subject.call(described_class.build_launch_message)
        end

        it "does not crash the subject" do
          expect(behaviour).to \
            receive(:handle_message) do |_, _|
              raise "bad behaviour"
            end

          expect {
            subject.call(handler_message)
          }.not_to raise_exception
        end
      end

      context "when cell crashes in next_timeout" do
        before do
          subject.call(described_class.build_launch_message)
        end

        it "does not crash the subject" do
          allow(behaviour).to \
            receive(:handle_message) do |state, _|
              state.persistent_data = "keep me around"
            end

          expect(behaviour).to \
            receive(:next_timeout) do |_, _|
              raise "bad behaviour"
            end

          expect {
            subject.call(handler_message)
          }.not_to raise_exception
        end
      end

      context "when cell crashes in handle_timeout" do
        before do
          subject.call(described_class.build_launch_message)
        end

        it "does not crash the subject" do
          next_timeout = Time.now

          allow(behaviour).to \
            receive(:handle_message) do |state, _|
              state.persistent_data = "keep me around"
            end

          allow(behaviour).to \
            receive(:next_timeout) do |_, _|
              next_timeout
            end

          expect(behaviour).to \
            receive(:handle_timeout) do |_, _|
              raise "bad behaviour"
            end

          delayed_message =
            expect_to_cause_one_delayed_message do
              subject.call(handler_message)
            end

          expect {
            subject.call(delayed_message)
          }.not_to raise_exception
        end
      end


      context "when cell does not exist" do
        before do
          subject.call(described_class.build_launch_message)
        end

        it "dispatches message to behaviour without persistent data" do
          expect(behaviour).to \
            receive(:handle_message) do |state, message|
              expect(message).to equal(cell_message)
              expect(state.persistent_data).to be_nil
            end

          subject.call(handler_message)
        end
      end

      context "when cell signals a timeout is necessary" do
        let(:handler_message) {
          described_class.build_message_to_cell(
            behaviour: behaviour,
            id: cell_id,
            cell_message: cell_message)
        }

        before do
          subject.call(described_class.build_launch_message)
        end

        it "uses timer to perform timeout message delivery" do
          next_timeout = nil
          allow(behaviour).to receive(:next_timeout) { |_|
            next_timeout
          }

          allow(behaviour).to \
            receive(:handle_message) do |state, _|
              state.persistent_data = "some data to keep cell alive"
              next_timeout = Time.now
            end

          emitted_message =
            expect_to_cause_one_delayed_message do
              subject.call(handler_message)
            end

          next_timeout = Time.now
          expect(behaviour).to receive(:handle_timeout) do
            next_timeout = nil
          end
          subject.call(emitted_message)
        end
      end
    end
  end

  describe "persistent storage bookkeeping" do
    declare_behaviour(:behaviour)

    let(:cell_id) { "cell id" }
    let(:cell_message) { "cell message" }
    let(:handler_message) {
      described_class.build_message_to_cell(
        behaviour: behaviour,
        id: cell_id,
        cell_message: cell_message)
    }

    context "when cell assigns to persistent_data" do
      before do
        subject.call(described_class.build_launch_message)
      end

      it "alters the persistent state" do
        allow(behaviour).to \
          receive(:handle_message) do |state, _|
            state.persistent_data = "new state"
          end

        expect {
          subject.call(handler_message)
        }.to change {
          persistent_hash
        }
      end
    end

    context "when cell clears persistent_data" do
      before do
        subject.call(described_class.build_launch_message)
      end

      it "clears obsolete slots in persistant storage" do
        allow(behaviour).to \
          receive(:handle_message) do |state, _|
          state.persistent_data = "new state"
        end

        subject.call(handler_message)
        expect(persistent_hash).not_to be_empty

        allow(behaviour).to \
          receive(:handle_message) do |state, _|
          state.persistent_data = nil
        end

        subject.call(handler_message)
        expect(persistent_hash).to be_empty
      end
    end
  end

  describe "timeout delivery" do
    context "at launch, with two behaviours with initial cell data" do
      declare_behaviour(:behaviour1)
      declare_behaviour(:behaviour2)

      let(:initial_data) { 1 }
      let(:cell_id) { "cell id" }

      before do
        # here, we make an assumption about internals!
        persistent_key = "#{behaviour1.behaviour_name}-#{cell_id}"
        persistent_hash[persistent_key] = initial_data
        persistent_key = "#{behaviour2.behaviour_name}-#{cell_id}"
        persistent_hash[persistent_key] = initial_data
      end

      it "emits a delayed message, upon which handle_timeout is called on both" do
        behaviour1_timeouts = [Time.now, Time.now]
        allow(behaviour1).to receive(:next_timeout) { |_|
          behaviour1_timeouts.pop
        }
        behaviour2_timeouts = [Time.now, Time.now]
        allow(behaviour2).to receive(:next_timeout) { |_|
          behaviour2_timeouts.pop
        }

        emitted_message =
          expect_to_cause_one_delayed_message do
            subject.call(described_class.build_launch_message)
          end

        expect(behaviour1).to receive(:handle_timeout)
        expect(behaviour2).to receive(:handle_timeout)
        subject.call(emitted_message)
      end
    end

    context "after launch" do
      declare_behaviour(:behaviour)

      before do
        subject.call(described_class.build_launch_message)
      end

      let(:cell_id) { "cell id" }
      let(:cell_message) { "cell message" }
      let(:handler_message) {
        described_class.build_message_to_cell(
          behaviour: behaviour,
          id: cell_id,
          cell_message: cell_message)
      }

      it "is not triggered again when no further timeout is demanded" do
        next_timeout = nil
        allow(behaviour).to receive(:next_timeout) { |_|
          next_timeout
        }

        allow(behaviour).to \
          receive(:handle_message) do |state, _|
            next_timeout = Time.now
            state.persistent_data = "some data to keep cell alive"
          end

        emitted_message =
          expect_to_cause_one_delayed_message do
            subject.call(handler_message)
          end

        next_timeout = Time.now
        expect(behaviour).to receive(:handle_timeout) do
          next_timeout = nil
        end

        expect_not_to_cause_a_delayed_message do
          subject.call(emitted_message)
        end
      end

      it "it not triggered when persistent data is cleared" do
        next_timeout = nil
        allow(behaviour).to receive(:next_timeout) { |_|
          next_timeout
        }

        allow(behaviour).to \
          receive(:handle_message) do |state, _|
            next_timeout = Time.now
            state.persistent_data = nil
          end

        expect_not_to_cause_a_delayed_message do
          subject.call(handler_message)
        end
      end
    end
  end
end

