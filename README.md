# FasterS3Url

Generate public and presigned AWS S3 `GET` URLs faster in ruby

The official [ruby AWS SDK](https://github.com/aws/aws-sdk-ruby) is actually quite slow and unoptimized when generating URLs to access S3 objects. If you are only creating a couple S3 URLs at a time this may not matter. But it can matter on the order of even two or three hundred at a time, especially when creating presigned URLs, for which the AWS SDK is especially un-optimized.

This gem provides a much faster implementation, by around an order of magnitude, for both public  and presigned S3 `GET` URLs.

## Usage

```ruby
signer = FasterS3Url::Builder.new(
  bucket_name: "my-bucket",
  region: "us-east-1",
  access_key_id: ENV['AWS_ACCESS_KEY'],
  secret_key_id: ENV['AWS_SECRET_KEY']
)

signer.public_url("my/object/key.jpg")
  #=> "https://my-bucket.aws"
signer.presigned_url("my/object/key.jpg")
```

You can re-use a signer object for convenience or slighlty improved performance. It should be concurrency-safe to share globally between threads.

If you are using S3 keys that need to be escaped in the URLs, this gem will escpae them properly.

When presigning URLs, you can pass the query parameters supported by S3 to control subsequent response headers. You can also supply a version_id for a URL to access a specific version.

```ruby
signer.presigned_url("my/object/key.jpg"
  response_cache_control: "public, max-age=604800, immutable",
  response_content_disposition: "attachment",
  response_content_language: "de-DE, en-CA",
  response_content_type: "text/html; charset=UTF-8",
  response_content_encoding: "deflate, gzip",
  response_expires: "Wed, 21 Oct 2030 07:28:00 GMT",
  version_id: "BspIL8pXg_52rGXELmqZ7cgmn7u4XJgS"
)
```

## Performance Benchmarking

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install local unreleased source of this gem onto your local machine for development, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Sources/Acknowledgements

[wt_s3_signer](https://github.com/WeTransfer/wt_s3_signer) served as a proof of concept, but was optimized for their particular use case, assuming batch processing where all signed S3 URLs share the same now time. I needed to support cases that didn't assume this, and also support custom headers like `response_content_disposition`. This code is also released with a different license. But if the API and use cases of `wt_s3_signer` meet your needs, it is even faster than this code.

I tried to figure out how to do the S3 presigned request from some AWS docs:

* https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
* https://docs.aws.amazon.com/general/latest/gr/sigv4-signed-request-examples.html

But these don't really have all info you need for generating an S3 signature. So also ended up debugger reverse engineering the ruby aws-sdk code when generating an S3 presigned url, for instance:

* https://github.com/aws/aws-sdk-ruby/blob/47c11bef18a4754ec8a05dfb637dcab120138c27/gems/aws-sdk-s3/lib/aws-sdk-s3/presigner.rb
* but especially: https://github.com/aws/aws-sdk-ruby/blob/47c11bef18a4754ec8a05dfb637dcab120138c27/gems/aws-sigv4/lib/aws-sigv4/signer.rb

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jrochkind/faster_s3_url.

I would love to hear from you!


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
