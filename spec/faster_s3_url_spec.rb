require 'spec_helper'
require 'aws-sdk-s3'

RSpec.describe FasterS3Url do
  let(:bucket_name) { "my-bucket" }
  let(:object_key) { "some/directory/file.jpg" }
  let(:region) { "us-east-1"}

  let(:aws_client) { Aws::S3::Client.new(region: region) }
  let(:aws_bucket) { Aws::S3::Bucket.new(name: bucket_name, client: aws_client)}

  let(:builder) { FasterS3Url::Builder.new(bucket_name: bucket_name, region: region) }

  describe "public URLs" do
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
      let(:builder) { FasterS3Url::Builder.new(host: host, bucket_name: bucket_name, region: region) }

      it "is correct" do
        expect(builder.public_url(object_key)).to eq("https://#{host}/#{object_key}")
      end
    end
  end


end
