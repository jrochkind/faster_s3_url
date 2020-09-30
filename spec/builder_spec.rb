require 'spec_helper'
require 'aws-sdk-s3'

# For the most part we actually spec that results match what aws-sdk-s3 itself would generate!
#
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
        let(:object_key) { "dir/dir/parens()=brackets[]punct';:\".jpg" }
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

        it "raises for too high" do
          expect {
            builder.presigned_url(object_key, expires_in: FasterS3Url::Builder::ONE_WEEK + 1)
          }.to raise_error(ArgumentError)
        end

        it "raises for too low" do
          expect {
            builder.presigned_url(object_key, expires_in: 0)
          }.to raise_error(ArgumentError)
        end
      end

      describe "custom S3 response_* headers" do

        # Aws-sdk for some reason does NOT sort query params canonically in actual
        # query, even though they have to be sorted canonically for signature.
        # We don't need to match it exactly if it has the SAME query params
        # INCLUDING same signature, which this tests
        def expect_equiv_uri(uri_str1, uri_str2)
          uri1 = URI.parse(uri_str1)
          uri2 = URI.parse(uri_str2)

          expect(uri1.scheme).to eq(uri2.scheme)
          expect(uri1.host).to eq(uri2.host)
          expect(uri1.path).to eq(uri2.path)

          expect(CGI.parse(uri1.query)).to eq(CGI.parse(uri1.query))
        end

        it "constructs equivalent custom response_cache_control" do
          expect_equiv_uri(
            builder.presigned_url(object_key, response_cache_control: "Private"),
            aws_bucket.object(object_key).presigned_url(:get, response_cache_control: "Private")
          )
        end

        it "constructs equivalent custom response_content_disposition" do
          content_disp =  "attachment; filename=\"foo bar.baz\"; filename*=UTF-8''foo%20bar.baz"
          expect_equiv_uri(
            builder.presigned_url(object_key, response_content_disposition: content_disp),
            aws_bucket.object(object_key).presigned_url(:get, response_content_disposition: content_disp)
          )
        end

        it "constructs equivalent custom response_content_language" do
          expect_equiv_uri(
            builder.presigned_url(object_key, response_content_language: "de-DE, en-CA"),
            aws_bucket.object(object_key).presigned_url(:get, response_content_language: "de-DE, en-CA")
          )
        end

        it "constructs equivalent custom response_content_language" do
          expect_equiv_uri(
            builder.presigned_url(object_key, response_content_type: "text/html; charset=UTF-8"),
            aws_bucket.object(object_key).presigned_url(:get, response_content_type: "text/html; charset=UTF-8")
          )
        end

        it "constructs equivalent custom response_content_encoding" do
          expect_equiv_uri(
            builder.presigned_url(object_key, response_content_encoding: "deflate, gzip"),
            aws_bucket.object(object_key).presigned_url(:get, response_content_encoding: "deflate, gzip")
          )
        end

        it "constructs equivalent custom response_expires" do
          expect_equiv_uri(
            builder.presigned_url(object_key, response_expires: "Wed, 21 Oct 2015 07:28:00 GMT"),
            aws_bucket.object(object_key).presigned_url(:get, response_expires: "Wed, 21 Oct 2015 07:28:00 GMT")
          )
        end

        it "constructs equivalent custom version_id" do
          version_id = "BspIL8pXg_52rGXELmqZ7cgmn7u4XJgS"

          expect_equiv_uri(
            builder.presigned_url(object_key, version_id: version_id),
            aws_bucket.object(object_key).presigned_url(:get, version_id: version_id)
          )
        end
      end
    end

    describe "with custom now" do
      let(:custom_now) { Date.today.prev_day.to_time }
      it "produces same as aws-sdk at that time" do
        expect(builder.presigned_url(object_key, time: custom_now)).to eq(aws_bucket.object(object_key).presigned_url(:get, time: custom_now))
      end
    end
  end

  describe "#url" do
    it "by default is public" do
      expect(builder.url(object_key)).to eq(builder.public_url(object_key))
    end

    it "can call public explicitly" do
      expect(builder.url(object_key, public: true)).to eq(builder.public_url(object_key))
    end

    it "can call presigned explicitly" do
      expect(builder.url(object_key, public: false, response_content_type: "image/jpeg")).to eq(builder.presigned_url(object_key, response_content_type: "image/jpeg"))
    end

    describe "with default_public set to false" do
      let(:builder) {
        FasterS3Url::Builder.new(bucket_name: bucket_name,
                                  region: region,
                                  host: host,
                                  access_key_id: access_key_id,
                                  secret_access_key: secret_access_key,
                                  default_public: false)
      }
      it "by default is presigned" do
        expect(builder.url(object_key)).to eq(builder.presigned_url(object_key))
      end
    end

    it "ignores inapplicable args when public" do
      expect(builder.url(object_key, public: true, response_content_type: "image/jpeg")).to eq(builder.public_url(object_key))
    end
  end
end
