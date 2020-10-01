# FasterS3Url

Generate public and presigned AWS S3 `GET` URLs faster in ruby

[![Gem Version](https://badge.fury.io/rb/faster_s3_url.svg)](https://badge.fury.io/rb/faster_s3_url) [![Build Status](https://travis-ci.com/jrochkind/faster_s3_url.svg?branch=master)](https://travis-ci.com/jrochkind/faster_s3_url)

The official [ruby AWS SDK](https://github.com/aws/aws-sdk-ruby) is actually quite slow and unoptimized when generating URLs to access S3 objects. If you are only creating a couple S3 URLs at a time this may not matter. But it can matter on the order of even two or three hundred at a time, especially when creating presigned URLs, for which the AWS SDK is especially un-optimized.

This gem provides a much faster implementation, by around an order of magnitude, for both public  and presigned S3 `GET` URLs. Additional S3 params such as `response-content-disposition` are supported for presigned URLs.

## Usage

```ruby
signer = FasterS3Url::Builder.new(
  bucket_name: "my-bucket",
  region: "us-east-1",
  access_key_id: ENV['AWS_ACCESS_KEY'],
  secret_access_key: ENV['AWS_SECRET_KEY']
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

Use a CNAME or CDN or any other hostname variant other than the default this gem will come up with? Just pass in a `host` argument to initializer. Will work with both public and presigned URLs.

```ruby
builder = FasterS3Url::Builder.new(
  bucket_name: "my-bucket.example.com",
  host: "my-bucket.example.com",
  region: "us-east-1",
  access_key_id: ENV['AWS_ACCESS_KEY'],
  secret_access_key: ENV['AWS_SECRET_KEY']
)
```

### Cache signing keys for further performance

Under most usage patterns, the presigend URLs you generate will all use a `time` with the same UTC date. In this case, a performance advantage can be had by asking the Builder to cache and re-use AWS signing keys, which only vary with calendar date of `time` arg, not time, or S3 key, or other args. It will actually cache the 5 most recently used signing keys.  This can result in around a 50% performance improvement with a re-used Builder used for generating presigned keys.

**NOTE WELL: This will technically make the Builder object no longer concurrency-safe under multiple threads.** Although you might get away with it under MRI. This is one reason it is not on by default.

```ruby
builder = FasterS3Url::Builder.new(
  bucket_name: "my-bucket.example.com",
  region: "us-east-1",
  access_key_id: ENV['AWS_ACCESS_KEY'],
  secret_access_key: ENV['AWS_SECRET_KEY'],
  cache_signing_keys: true
)
builder.presign_url(key) # performance enhanced
```


### Automatic AWS credentials lookup?

Right now, you need to explicitly supply `access_key_id` and `secret_access_key`, in part to avoid a dependency on the AWS SDK (This gem doesn't have such a dependency!). Let us know if this makes you feel a certain kind of way.

If you want to look up key/secret/region using the standard SDK methods of checking various places, in order to supply them to the `FasterS3Url::Builder`, you can try this (is there a better way? Cause this is kind of a mess!)

```ruby
require 'aws-sdk-s3'
client = Aws::S3::Client.new
credentials = client.config.credentials
credentails = credentials.credentials if credentials.respond_to?(:credentials)

access_key_id     = credentials.access_key_id
secret_access_key = credentials.secret_access_key
region            = client.config.region
```

### Shrine Storage

Use [shrine](https://shrinerb.com/)?  We do and love it. This gem provides a storage that can be a drop-in replacement to [Shrine::Storage::S3](https://shrinerb.com/docs/storage/s3) (shrine 3.x required), but with faster URL generation.

```ruby
# Where you might have done:

require "shrine/storage/s3"

s3 = Shrine::Storage::S3.new(
  bucket: "my-app", # required
  region: "eu-west-1", # required
  access_key_id: "abc",
  secret_access_key: "xyz",
)

# instead do:

require "faster_s3_url/shrine/storage"

s3 = FasterS3Url::Shrine::Storage.new(
  bucket: "my-app", # required
  region: "eu-west-1", # required
  access_key_id: "abc", # required
  secret_access_key: "xyz", # required
)
```

A couple minor differences, let me know if they disrupt you:
* We don't support the `signer` initializer argument, not clear to me why you'd want to use this gem if you are using it.
* We support a `host` arg in initializer, but not in #url method.

## Performance Benchmarking

Benchmarks were done using scripts checked into repo at `./perf` (which use benchmark-ips with mode `:stats => :bootstrap, :confidence => 95`), on my 2015 Macbook Pro, using ruby MRI 2.6.6. Benchmarking is never an exact science, hopefully this is reasonable.

In my narrative, I normalize to how many iterations can happen in **10ms** to have numbers closer to what might be typical use cases.

### Public URLs

`aws-sdk-s3` can create about 180 public URLs in 10ms, not horrible, but for how simple it seems the operation should be? FasterS3Url can do 2,200 public URLs in 10ms, that's a lot better.

```
$ bundle exec ruby perf/public_bench.rb
Warming up --------------------------------------
          aws-sdk-s3     1.265k i/100ms
         FasterS3Url    24.414k i/100ms
Calculating -------------------------------------
          aws-sdk-s3     18.701k (± 3.2%) i/s -     92.345k in   5.048062s
         FasterS3Url    222.938k (± 3.2%) i/s -      1.123M in   5.106971s
                   with 95.0% confidence
```

### Presigned URLs

Here's where it really starts to matter.

`aws-sdk-s3` can only generate about 10 presigned URLs in 10ms, painful. FasterS3URL, with a re-used Builder object, can generate about 220 presigned URLs in 10ms, much better, and actually faster than `aws-sdk-s3` can generate public urls!  Even if we re-instantiate a Builder each time, we can generate 180 presigned URLs in 10ms, don't lose too much performance that way.

If we re-use the Builder *and* turn on the (not thread-safe) `cached_signing_keys` option, we can get up to 300 presigned URLs generated in 10ms.

FasterS3URL supports supplying custom query params to instruct s3 HTTP response headers. This does slow things down since they need to be URI-escaped and constructed. Using this feature with `aws-sdk-s3`, it doesn't lose much speed, down to 9 instead of 10 URLs in 10ms. FasterS3URL goes down from 210 to 180 URLs generated in 10ms (without using `cached_signing_keys` option).

We can compare to the ultra-fast [wt_s3_signer](https://github.com/WeTransfer/wt_s3_signer) gem, which, with a re-used signer object (that assumes the same `time` for all URLs, unlike us; and does not support per-url custom query params) can get all the way up to 680 URLs generated in 10ms, over twice as fast as we can do even with `cached_signing_keys`. If the restrictions and API of wt_s3_signer are amenable to your use case, it's definitely the fastest. But FasterS3URL is in the ballpark, and still more than an order of magnitude faster than `aws-sdk-s3`.

```
$ bundle exec ruby perf/presigned_bench.rb
Warming up --------------------------------------
          aws-sdk-s3   113.000  i/100ms
aws-sdk-s3 with custom headers
                        95.000  i/100ms
 re-used FasterS3Url     1.820k i/100ms
re-used FasterS3Url with cached signing keys
                         2.920k i/100ms
re-used FasterS3URL with custom headers
                         1.494k i/100ms
new FasterS3URL Builder each time
                         1.977k i/100ms
re-used WT::S3Signer     7.985k i/100ms
new WT::S3Signer each time
                         1.611k i/100ms
Calculating -------------------------------------
          aws-sdk-s3      1.084k (± 4.2%) i/s -      5.311k in   5.003981s
aws-sdk-s3 with custom headers
                        918.315  (± 4.8%) i/s -      4.560k in   5.118770s
 re-used FasterS3Url     21.906k (± 4.0%) i/s -    107.380k in   5.046561s
re-used FasterS3Url with cached signing keys
                         29.756k (± 3.6%) i/s -    146.000k in   4.999910s
re-used FasterS3URL with custom headers
                         18.062k (± 4.3%) i/s -     85.158k in   5.025685s
new FasterS3URL Builder each time
                         18.312k (± 3.9%) i/s -     90.942k in   5.098636s
re-used WT::S3Signer     68.275k (± 3.5%) i/s -    343.355k in   5.109088s
new WT::S3Signer each time
                         22.425k (± 2.8%) i/s -    111.159k in   5.036814s
                   with 95.0% confidence
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install local unreleased source of this gem onto your local machine for development, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Sources/Acknowledgements

[wt_s3_signer](https://github.com/WeTransfer/wt_s3_signer) served as a proof of concept, but was optimized for their particular use case, assuming batch processing where all signed S3 URLs share the same "now" time. I needed to support cases that didn't assume this, and also support custom headers like `response_content_disposition`. This code is also released with a different license. But if the API and use cases of `wt_s3_signer` meet your needs, it is even faster than this code.

I tried to figure out how to do the S3 presigned request from some AWS docs:

* https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
* https://docs.aws.amazon.com/general/latest/gr/sigv4-signed-request-examples.html

But these don't really have all info you need for generating an S3 signature. So also ended up debugger reverse engineering the ruby aws-sdk code when generating an S3 presigned url, for instance:

* https://github.com/aws/aws-sdk-ruby/blob/47c11bef18a4754ec8a05dfb637dcab120138c27/gems/aws-sdk-s3/lib/aws-sdk-s3/presigner.rb
* but especially: https://github.com/aws/aws-sdk-ruby/blob/47c11bef18a4754ec8a05dfb637dcab120138c27/gems/aws-sigv4/lib/aws-sigv4/signer.rb

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jrochkind/faster_s3_url.

Is there a feature missing that you need? I may not be able to provide it, but I would love to hear from you!

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
