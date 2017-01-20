require 'datamill/dependencies_resolver'

describe Datamill::DependenciesResolver do
  subject {
    described_class.new(container)
  }

  def self.declare_container
    let(:container) {
      Class.new do
        class_eval(&Proc.new)
      end.new
    }
  end

  describe "#call" do
    context "when a non-existent entry is requested directly" do
      let(:container) {
        Object.new
      }

      it "raises the appropriate exception" do
        expect {
          subject.call(:nonexistent)
        }.to raise_exception(Datamill::DependenciesResolver::UnknownEntry)
      end
    end

    context "when a non-existent entry is requested indirectly as a dependency" do
      declare_container do
        def node(nonexistent)
        end
      end

      it "raises the appropriate exception" do
        expect {
          subject.call(:node)
        }.to raise_exception(Datamill::DependenciesResolver::UnknownEntry)
      end
    end

    context "when a node references itself as a dependency" do
      declare_container do
        def node(node)
        end
      end

      it "raises the appropriate exception" do
        expect {
          subject.call(:node)
        }.to raise_exception(Datamill::DependenciesResolver::CircularReference)
      end
    end

    context "when a node references itself as a deep dependency" do
      declare_container do
        def node(deep)
        end

        def deep(deeper)
        end

        def deeper(node)
        end
      end

      it "raises the appropriate exception" do
        expect {
          subject.call(:node)
        }.to raise_exception(Datamill::DependenciesResolver::CircularReference)
      end
    end

    context "successfully resolving" do
      declare_container do
        def node(deep)
          Struct.new(:deep).new(deep)
        end

        def deep
          "deep"
        end

        def has_named_dep(named_dep:)
          Struct.new(:named_dep).new(named_dep)
        end

        def named_dep
          5
        end
      end

      it "returns the same object over and over" do
        expect(
          subject.call(:node)
        ).to \
          be_equal(
            subject.call(:node)
          )

        expect(
          subject.call(:node).deep
        ).to \
          be_equal(
            subject.call(:deep)
          )
      end

      it "can be used with dependencies declared as named arguments" do
        expect(
          subject.call(:has_named_dep).named_dep
        ).to \
          be_equal(
            subject.call(:named_dep)
          )
      end
    end
  end
end

