require 'datamill/persistent_hash/as_json'

describe Datamill::PersistentHash::AsJson do
  let(:decorated) do
    require 'datamill/persistent_hash/redis'
    instance_double(Datamill::PersistentHash::Redis)
  end

  let(:backend_stub) { {} }
  before do
    # we have this effort so we can benefit from verifying
    # doubles. It would be nice to be able to simplify this setup...
    allow(decorated).to receive(:[]) { |key|
      backend_stub[key]
    }
    allow(decorated).to receive(:[]=) { |key, value|
      backend_stub[key] = value
    }
  end

  subject {
    described_class.new(decorated)
  }

  describe "#keys" do
    it "delegates" do
      keys = double
      expect(decorated).to receive(:keys) { keys }

      expect(subject.keys).to eql(keys)
    end
  end

  describe "#[]" do
    it "reports absent slots with a nil return value" do
      expect(subject[""]).to be_nil
    end
  end

  describe "#[]= followed by #[]" do
    let(:key) { "key" }

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


      subject[key] = bad_as_json
      expect(subject[key]).to eql(bad_as_json)
    end
  end

  describe "#delete" do
    let(:key) { "key" }

    it "delegates" do
      expect(decorated).to receive(:delete).with(key)
      subject.delete key
    end
  end
end

