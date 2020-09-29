require 'spec_helper'
require 'aws-sdk-s3'

RSpec.describe FasterS3Url do
  let(:access_key_id) { "fakeExampleAccessKeyId"}
  let(:secret_access_key) { "fakeExampleSecretAccessKey" }

  let(:bucket_name) { "my-bucket" }
  let(:object_key) { "some/directory/file.jpg" }
  let(:region) { "us-east-1"}
  let(:host) { nil }

  let(:aws_client) { Aws::S3::Client.new(region: region, access_key_id: access_key_id, secret_access_key: secret_access_key) }
  let(:aws_bucket) { Aws::S3::Bucket.new(name: bucket_name, client: aws_client)}

  let(:builder) {
    FasterS3Url::Builder.new(bucket_name: bucket_name,
                              region: region,
                              host: host,
                              access_key_id: access_key_id,
                              secret_access_key: secret_access_key)
  }

  describe "#public_url" do
    it "are produced" do
      expect(builder.public_url(object_key)).to eq("https://#{bucket_name}.s3.amazonaws.com/#{object_key}")
      expect(builder.public_url(object_key)).to eq(aws_bucket.object(object_key).public_url)
    end


    describe "with other region" do
      let(:region) { "us-west-2" }

      it "is correct" do
        expect(builder.public_url(object_key)).to eq("https://#{bucket_name}.s3.#{region}.amazonaws.com/#{object_key}")
        expect(builder.public_url(object_key)).to eq(aws_bucket.object(object_key).public_url)
      end
    end

    describe "keys that needs escaping" do
      describe "space" do
        let(:object_key) { "dir/dir/one two.jpg" }
        it "is correct" do
          expect(builder.public_url(object_key)).to eq(aws_bucket.object(object_key).public_url)
        end
      end

      describe "tilde" do
        let(:object_key) { "dir/~dir/file.jpg" }
        it "is correct" do
          expect(builder.public_url(object_key)).to eq(aws_bucket.object(object_key).public_url)
        end
      end

      describe "other escapable" do
        let(:object_key) { "dir/dir/parens()brackets[]punct';:\".jpg" }
        it "is correct" do
          expect(builder.public_url(object_key)).to eq(aws_bucket.object(object_key).public_url)
        end
      end
    end

    describe "custom host" do
      let(:host) { "my.example.com" }

      it "is correct" do
        expect(builder.public_url(object_key)).to eq("https://#{host}/#{object_key}")
      end
    end
  end

  describe "#presigned_url" do
    describe "with frozen time" do
      around do |example|
        Timecop.freeze(Time.now)

        example.run

        Timecop.return
      end

      it "produces same as aws-sdk" do
        expect(builder.presigned_url(object_key)).to eq(aws_bucket.object(object_key).presigned_url(:get))
      end

      describe "custom expires_in" do
        let(:expires_in) { 4 * 24 * 60 * 60}
        it "produces saem as aws-sdk" do
          expect(builder.presigned_url(object_key, expires_in: expires_in)).to eq(aws_bucket.object(object_key).presigned_url(:get, expires_in: expires_in))
        end
      end
    end

    describe "with custom now" do
      let(:custom_now) { Date.today.prev_day.to_time }
      it "produces same as aws-sdk at that time" do
        expect(builder.presigned_url(object_key, now: custom_now)).to eq(aws_bucket.object(object_key).presigned_url(:get, time: custom_now))
      end
    end
  end
end
