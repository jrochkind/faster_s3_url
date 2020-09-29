# Run as eg:
#
# $ bundle exec ruby perf/public_bench.rb

require 'benchmark/ips'
require 'faster_s3_url'
require 'aws-sdk-s3'

access_key_id =  "fakeExampleAccessKeyId"
secret_access_key = "fakeExampleSecretAccessKey"

bucket_name = "my-bucket"
object_key =  "some/directory/file.jpg"
region = "us-east-1"

aws_client = Aws::S3::Client.new(region: region, access_key_id: access_key_id, secret_access_key: secret_access_key)
aws_bucket = Aws::S3::Bucket.new(name: bucket_name, client: aws_client)

faster_s3_builder = FasterS3Url::Builder.new(region: region, access_key_id: access_key_id, secret_access_key: secret_access_key, bucket_name: bucket_name)

Benchmark.ips do |x|
  begin
    require 'kalibera'
    x.config(:stats => :bootstrap, :confidence => 95)
  rescue LoadError

  end


  x.report("aws-sdk-s3") do
    aws_bucket.object(object_key).public_url
  end

  x.report("FasterS3Url") do
    faster_s3_builder.public_url(object_key)
  end
end

