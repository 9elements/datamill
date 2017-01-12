require 'datamill/cell/base'
require 'datamill/cell/state'

describe Datamill::Cell::Base do
  let(:instance_proxy) do
    double "instance proxy"
  end

  let(:cell_class) do
    instance_proxy = instance_proxy()

    Class.new(described_class) do
      # For the sake of testing:
      @instance_proxy = instance_proxy
      singleton_class.send :attr_reader, :instance_proxy

      def self.name
        "Cell Class"
      end

      def self.new(*)
        @instance ||= super
      end

      # Stub implementation of a cell class

      unserialize_cell_id_to(:first_identifier, :second_identifier) do |cell_id|
        JSON.parse(cell_id)
      end

      def self.identify_cell(first_identifier, second_identifier)
        { first_identifier: first_identifier, second_identifier: second_identifier }.to_json
      end

      def frobnicate(*args)
        self.class.instance_proxy.frobnicate(self, *args)
      end

      def next_timeout
        self.class.instance_proxy.next_timeout(self)
      end

      def handle_timeout
        self.class.instance_proxy.handle_timeout(self)
      end
    end
  end

  let(:proxy_for_args) do
    # cells can be identified by a compound identifier. proxy_for accepts multiple arguments for that.
    ["first identifying arg", "second identifying arg"]
  end

  describe ".behaviour" do
    subject { cell_class.behaviour }

    it "mangles behaviour_name from the name of the cell class" do
      expect(cell_class.name).not_to be_empty # test sanity

      expect(subject.behaviour_name).to include(cell_class.name)
    end
  end

  describe "interaction between behaviour and cell class" do
    let(:initial_persistent_data) { double "initial persistent data" }

    describe "proxying" do
      let(:method_arguments) { [1, "foo"] }

      let(:proxy_helper) do
        double "proxy helper"
      end

      it "dispatches a proxy method call to the instantiated cell" do
        received = nil
        allow(proxy_helper).to receive(:call) do |serialized_id, packed_method|
          received = [serialized_id, packed_method]
        end

        expect {
          cell_class.proxy_for(*proxy_for_args, proxy_helper: proxy_helper)
            .frobnicate(*method_arguments)
        }.to change { received }

        serialized_id, packed_method = received
        cell_state = build_cell_state(serialized_id)

        expect(instance_proxy).to receive(:frobnicate) do |instance, *args|
          expect(args).to eql(method_arguments)

          expect_instance_to_be_properly_set_up instance,
            persistent_data: initial_persistent_data

          expect_instance_to_delegate_change_of_persistent_data instance,
            cell_state: cell_state
        end

        cell_class.behaviour.handle_message(cell_state, packed_method)
      end
    end

    describe "dispatching of behaviour messages" do
      let(:serialized_id) do
        cell_class.identify_cell(*proxy_for_args)
      end

      let(:cell_state) do
        build_cell_state(serialized_id)
      end

      let(:timeout_return) { double "timeout return" }

      it "dispatches next_timeout to the instantiated cell" do
        expect(instance_proxy).to receive(:next_timeout) do |instance|
          expect_instance_to_be_properly_set_up instance,
            persistent_data: initial_persistent_data

          timeout_return
        end

        expect(
          cell_class.behaviour.next_timeout(cell_state)
        ).to be(timeout_return)
      end

      it "dispatches handle_timeout to the instantiated cell" do
        expect(instance_proxy).to receive(:handle_timeout) do |instance|
          expect_instance_to_be_properly_set_up instance,
            persistent_data: initial_persistent_data

          expect_instance_to_delegate_change_of_persistent_data instance,
            cell_state: cell_state
        end

        cell_class.behaviour.handle_timeout(cell_state)
      end
    end

    def expect_instance_to_be_properly_set_up(instance, persistent_data:)
      expect(instance.persistent_data).to be(initial_persistent_data)

      # Dynamic attributes declared with unserialize_cell_id_to:
      expect(instance.first_identifier).to eql(proxy_for_args.first)
      expect(instance.second_identifier).to eql(proxy_for_args.last)
    end

    def expect_instance_to_delegate_change_of_persistent_data(instance, cell_state:)
      expect {
        instance.persistent_data = "new data"
      }.to change { cell_state.persistent_data }
    end

    def build_cell_state(serialized_id)
      Datamill::Cell::State.new(
        behaviour: cell_class.behaviour,
        persistent_data: initial_persistent_data,
        id: serialized_id
      )
    end
  end
end

