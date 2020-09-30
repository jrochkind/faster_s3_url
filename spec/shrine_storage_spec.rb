require 'spec_helper'
require 'faster_s3_url/shrine/storage'

# We're not gonna test everything and make sure it's good as a storage, we just
# assume our light sub-class is doing what it's superclass is doing. Famous last words,
# but it gets very complicated to test otherwise.
#
RSpec.describe FasterS3Url::Shrine::Storage do
  let(:access_key_id) { "fakeExampleAccessKeyId"}
  let(:secret_access_key) { "fakeExampleSecretAccessKey" }

  let(:bucket_name) { "my-bucket" }
  let(:object_key) { "some/directory/file.jpg" }
  let(:region) { "us-east-1"}

  let(:storage) do
    FasterS3Url::Shrine::Storage.new(
      bucket: bucket_name,
      region: region,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key
    )
  end

  let(:builder) do
    FasterS3Url::Builder.new(bucket_name: bucket_name,
                              region: region,
                              access_key_id: access_key_id,
                              secret_access_key: secret_access_key)
  end

  it "produces presigned url by default" do
    expect(storage.url(object_key)).to eq(builder.presigned_url(object_key))
  end

  it "can produce public url" do
    expect(storage.url(object_key, public: true)).to eq(builder.public_url(object_key))
  end

  it "raises on signer initialize" do
    expect {
      FasterS3Url::Shrine::Storage.new(
        bucket: bucket_name,
        region: region,
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        signer: lambda {|obj| obj }
      )
    }.to raise_error(ArgumentError)
  end

  describe "with public initializer" do
    let(:storage) do
      FasterS3Url::Shrine::Storage.new(
        bucket: bucket_name,
        region: region,
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        public: true
      )
    end

    it "produces public urls by default" do
      expect(storage.url(object_key)).to eq(builder.public_url(object_key))
    end

    it "can produce presigned urls by choice" do
      expect(storage.url(object_key, public: false)).to eq(builder.presigned_url(object_key))
    end

    it "can produce presigned urls with query params" do
      params = {
        response_content_type: "image/jpeg",
        response_content_disposition: "attachment; filename=\"foo bar.baz\"; filename*=UTF-8''foo%20bar.baz"
      }

      expect(
        storage.url(object_key, public: false, **params)
      ).to eq(
        builder.presigned_url(object_key, **params)
      )
    end
  end

  describe "with shrine prefix" do
    let(:prefix) { "foo/bar" }
    let(:storage) do
      FasterS3Url::Shrine::Storage.new(
        bucket: bucket_name,
        region: region,
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        prefix: prefix
      )
    end

    it "produces urls with prefix" do
      expect(storage.url(object_key, public: true)).to eq(builder.public_url( "#{prefix}/#{object_key}" ))
    end
  end

  describe "with host initializer" do
    let(:host) { "my.example.org" }

    let(:storage) do
      FasterS3Url::Shrine::Storage.new(
        bucket: bucket_name,
        region: region,
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        host: host
      )
    end

    let(:builder) do
      FasterS3Url::Builder.new(bucket_name: bucket_name,
                                region: region,
                                access_key_id: access_key_id,
                                secret_access_key: secret_access_key,
                                host: host)
    end

    it "respects when generating" do
      expect(storage.url(object_key, public: true)).to eq(builder.public_url(object_key))
    end

  end
end
