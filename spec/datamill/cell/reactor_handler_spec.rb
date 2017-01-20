require 'datamill/cell/reactor_handler'
require 'datamill/cell/behaviour'

describe Datamill::Cell::ReactorHandler do
  let(:persistent_hash) { {} }
  let(:delayed_message_emitter) { double "delayed message emitter" }

  let(:behaviours) { [] }

  def self.declare_behaviour(name)
    let(name) do
      instance_double(Datamill::Cell::Behaviour.singleton_class, behaviour_name: name.to_s)
    end

    before do
      behaviours << send(name)
    end
  end

  subject {
    result =
      described_class.new(
        persistent_hash: persistent_hash,
        delayed_message_emitter: delayed_message_emitter
      )

    behaviours.each do |behaviour|
      result.register_behaviour behaviour
    end

    result
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
          allow(behaviour).to receive(:nop) { |state|
            state.next_timeout = Time.now
          }

          emitted_message =
            expect_to_cause_one_delayed_message do
              subject.call(described_class.build_launch_message)
            end

          expect(behaviour).to receive(:handle_timeout)
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

      context "when cell crashes in handle_timeout" do
        before do
          subject.call(described_class.build_launch_message)
        end

        it "does not crash the subject" do
          allow(behaviour).to \
            receive(:handle_message) do |state, _|
              state.persistent_data = "keep me around"
              state.next_timeout = Time.now
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
          allow(behaviour).to \
            receive(:handle_message) do |state, _|
              state.persistent_data = "some data to keep cell alive"
              state.next_timeout = Time.now
            end

          emitted_message =
            expect_to_cause_one_delayed_message do
              subject.call(handler_message)
            end

          expect(behaviour).to receive(:handle_timeout)
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

      it "delivers independent handle_timeout messages when behaviours demanded it in `.nop`" do
        allow(behaviour1).to receive(:nop) { |state|
          state.next_timeout = Time.now
        }
        allow(behaviour2).to receive(:nop) { |state|
          state.next_timeout = Time.now
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
        allow(behaviour).to \
          receive(:handle_message) do |state, _|
            state.persistent_data = "some data to keep cell alive"
            state.next_timeout = Time.now
          end

        emitted_message =
          expect_to_cause_one_delayed_message do
            subject.call(handler_message)
          end

        expect(behaviour).to receive(:handle_timeout) do |state|
          # not demanding a further timeout here means we don't change this condition:
          expect(state.next_timeout).to be_nil
        end

        expect_not_to_cause_a_delayed_message do
          subject.call(emitted_message)
        end
      end

      it "it not triggered when persistent data is cleared" do
        allow(behaviour).to \
          receive(:handle_message) do |state, _|
            state.persistent_data = nil
            state.next_timeout = Time.now
          end

        expect_not_to_cause_a_delayed_message do
          subject.call(handler_message)
        end
      end
    end
  end
end

