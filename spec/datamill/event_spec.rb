require 'datamill/event'

describe Datamill::Event do
  let(:event_class) do
    Class.new(described_class) do
      def self.event_name
        "event_class"
      end

      attribute :key
    end
  end

  def build_hash(event_cls, data = {})
    # this should be the only place we assume internal knowledge ;)
    data.merge("datamill_event" => event_cls.event_name)
  end

  it "has attributes" do
    expect(
      event_class.new(build_hash(event_class, "key" => "value")).key
    ).to eql("value")

    event = event_class.new(build_hash(event_class, "key" => "value"))
    expect {
      event.key = "new value"
    }.to change { event.key }.to("new value")
  end

  it "can be constructed from a hash" do
    event_class.new(build_hash(event_class))
  end

  it "can be converted to a hash" do
    expect(
      event_class.new.to_h
    ).to be_instance_of(Hash)

    initial_hash = build_hash(event_class)
    expect(
      event_class.new(initial_hash).to_h
    ).to eql(initial_hash)
  end

  it "can be serialized as JSON" do
    initial_hash = build_hash(event_class)
    expect(
      event_class.new(initial_hash).to_json
    ).to eql(initial_hash.to_json)
  end

  describe ".===" do
    let(:another_event_class) do
      Class.new(described_class) do
        def self.event_name
          "another_event_class"
        end
      end
    end

    it "case-equals an instance of itself" do
      expect(
        event_class
      ).to CaseEqualityMatcher.new(event_class.new)
    end

    it "does not case-equal an instance of a different subclass" do
      expect(
        event_class
      ).not_to CaseEqualityMatcher.new(another_event_class.new)
    end

    it "case-equals a hash representation of an instance" do
      initial_hash = build_hash(event_class)
      expect(
        event_class
      ).to CaseEqualityMatcher.new(event_class.new(initial_hash).to_h)

      expect(
        event_class
      ).to CaseEqualityMatcher.new(event_class.new.to_h)
    end
  end

  class CaseEqualityMatcher
    def initialize(rhs)
      @rhs = rhs
    end

    def matches?(lhs)
      lhs === @rhs
    end

    def failure_message
      "meh."
    end

    def failure_message_when_negated
      "meh."
    end
  end
end

