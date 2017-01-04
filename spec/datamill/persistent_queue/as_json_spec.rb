require 'datamill/persistent_queue/as_json'

describe Datamill::PersistentQueue::AsJson do
  let(:backing_queue) { [] }
  let(:decorated) {
    require 'datamill/persistent_queue/redis'
    double(Datamill::PersistentQueue::Redis)
  }

  before do
    allow(decorated).to receive(:push) do |item|
      backing_queue.push item
    end
    allow(decorated).to receive(:blocking_peek) do
      backing_queue.first
    end
  end

  subject {
    described_class.new(decorated)
  }

  describe "#push followed by #blocking_peek" do
    it "works even on values that are not JSON parsable" do
      # sanity check demonstrating the problem
      bad_as_json = "foo"
      expect {
        JSON.parse(bad_as_json.to_json)
      }.to raise_exception(JSON::ParserError)

      good_as_json = []
      expect {
        JSON.parse(good_as_json.to_json)
      }.not_to raise_exception

      subject.push bad_as_json
      expect(subject.blocking_peek).to eql(bad_as_json)
    end
  end

  describe "#seek" do
    it "delegates" do
      expect(decorated).to receive(:seek)
      subject.seek
    end
  end
end
