gem "shrine", "~> 3.0"
require 'shrine/storage/s3'

module FasterS3Url
  module Shrine
    # More or less a drop-in replacement for Shrine::Storage::S3 , that uses FasterS3Url faster S3 URL generation.
    # https://shrinerb.com/docs/storage/s3
    #
    #     require 'faster_s3_url/storage/shrine'
    #
    #     s3 = FasterS3Url::Shrine::Storage.new(
    #       bucket: "my-app", # required
    #       region: "eu-west-1", # required
    #       access_key_id: "abc",
    #       secret_access_key: "xyz"
    #     )
    #
    # A couple incompatibilities with Shrine::Storage::S3, which I don't expect to cause problems
    # for anyone but if they do please let me know.
    #
    #  * we do not support the :signer option in initialier (why would you want to use that with this? Let me know)
    #
    #  * We support a `host` option on initializer, but do NOT support the `host` option on #url (I don't underestand
    #  why it's per-call in the first place, do you need it to be?)
    #
    #  * You DO need to supply access_key_id and secret_access_key in initializer, they can not be automatically
    #  looked up from AWS environmental chain. See README.
    #
    class Storage < ::Shrine::Storage::S3
      # Same options as Shrine::Storage::S3, plus `host`
      def initialize(**options)
        if options[:signer]
          raise ArgumentError.new("#{self.class.name} does not support :signer option of Shrine::Storage::S3. Should it? Let us know.")
        end

        host = options.delete(:host)
        @faster_s3_url_builder = FasterS3Url::Builder.new(
          bucket_name: options[:bucket],
          access_key_id: options[:access_key_id],
          secret_access_key: options[:secret_access_key],
          region: options[:region],
          host: host)

        super(**options)
      end

      # unlike base Shrine::Storage::S3, does not support `host` here, do it in
      # initializer instead. Is there a really use case for doing it here?
      # If so let us know.
      #
      # options are ignored when public mode, so you can send options the same
      # for public or not, and not get an error on public for options only appropriate
      # to presigned.
      #
      # Otherwise, same options as Shrine::S3::Storage should be supported, please
      # see docs there. https://shrinerb.com/docs/storage/s3
      def url(id, public: self.public, **options)
        @faster_s3_url_builder.url(object_key(id), public: public, **options)
      end

      # For older shrine versions without it, we need this...
      unless self.method_defined?(:object_key)
        def object_key(id)
          [*prefix, id].join("/")
        end
      end
    end
  end
end
