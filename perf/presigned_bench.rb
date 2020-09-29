# Run as eg:
#
# $ bundle exec ruby perf/presigned_bench.rb

require 'benchmark/ips'
require 'faster_s3_url'
require 'aws-sdk-s3'
require 'wt_s3_signer'

access_key_id =  "fakeExampleAccessKeyId"
secret_access_key = "fakeExampleSecretAccessKey"

bucket_name = "my-bucket"
object_key =  "some/directory/file.jpg"
region = "us-east-1"

aws_client = Aws::S3::Client.new(region: region, access_key_id: access_key_id, secret_access_key: secret_access_key)
aws_bucket = Aws::S3::Bucket.new(name: bucket_name, client: aws_client)

faster_s3_builder = FasterS3Url::Builder.new(region: region, access_key_id: access_key_id, secret_access_key: secret_access_key, bucket_name: bucket_name)

wt_signer = WT::S3Signer.new(
                    expires_in: 15 * 60,
                    aws_region: "us-east-1",
                    bucket_endpoint_url: "https://#{bucket_name}.s3.amazonaws.com",
                    bucket_host: "#{bucket_name}.s3.amazonaws.com",
                    bucket_name: bucket_name,
                    access_key_id: access_key_id,
                    secret_access_key: secret_access_key,
                    session_token: nil
)

Benchmark.ips do |x|
  begin
    require 'kalibera'
    x.config(:stats => :bootstrap, :confidence => 95)
  rescue LoadError

  end

  x.report("aws-sdk-s3") do
    aws_bucket.object(object_key).presigned_url(:get)
  end

  x.report("aws-sdk-s3 with custom headers") do
    aws_bucket.object(object_key).presigned_url(:get, response_content_type: "image/jpeg", response_content_disposition: "attachment; filename=\"foo bar.baz\"; filename*=UTF-8''foo%20bar.baz")
  end

  x.report("re-used FasterS3Url") do
    faster_s3_builder.presigned_url(object_key)
  end

  x.report("re-used FasterS3URL with custom headers") do
    faster_s3_builder.presigned_url(object_key, response_content_type: "image/jpeg", response_content_disposition: "attachment; filename=\"foo bar.baz\"; filename*=UTF-8''foo%20bar.baz")
  end

  x.report("new FasterS3URL Builder each time") do
    builder = FasterS3Url::Builder.new(region: region, access_key_id: access_key_id, secret_access_key: secret_access_key, bucket_name: bucket_name)
    builder.presigned_url(object_key)
  end

  x.report("re-used WT::S3Signer") do
    wt_signer.presigned_get_url(object_key: object_key)
  end

end

