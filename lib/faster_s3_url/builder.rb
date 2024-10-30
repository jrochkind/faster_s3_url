# frozen_string_literal: true

require 'cgi'

module FasterS3Url
  # Signing algorithm based on Amazon docs at https://docs.aws.amazon.com/general/latest/gr/sigv4-signed-request-examples.html ,
  # as well as some interactive code reading of Aws::Sigv4::Signer
  # https://github.com/aws/aws-sdk-ruby/blob/6114bc9692039ac75c8292c66472dacd14fa6f9a/gems/aws-sigv4/lib/aws-sigv4/signer.rb
  # as used by Aws::S3::Presigner https://github.com/aws/aws-sdk-ruby/blob/6114bc9692039ac75c8292c66472dacd14fa6f9a/gems/aws-sdk-s3/lib/aws-sdk-s3/presigner.rb
  class Builder
    FIFTEEN_MINUTES = 60 * 15
    ONE_WEEK = 60 * 60 * 24 * 7

    SIGNED_HEADERS = "host".freeze
    METHOD = "GET".freeze
    ALGORITHM = "AWS4-HMAC-SHA256".freeze
    SERVICE = "s3".freeze

    DEFAULT_EXPIRES_IN = FIFTEEN_MINUTES # 15 minutes, seems to be AWS SDK default

    MAX_CACHED_SIGNING_KEYS = 5

    attr_reader :bucket_name, :region, :host, :access_key_id, :session_token
    private attr_reader :base_url, :base_path

    # @option params [String] :bucket_name required
    #
    # @option params [String] :region eg "us-east-1", required
    #
    # @option params[String] :host optional, host to use in generated URLs. If empty, will construct default AWS S3 host for bucket name and region.
    #
    # @option params[String] :endpoint optional. `endpoint` as in AWS SDK S3, to point at non-standard AWS locations. Mutually exclusive with `host`, can be used to point to alternate systems including local S3 clones like minio.
    #
    # @option params [String] :access_key_id required at present, change to allow look up from environment using standard aws sdk routines?
    #
    # @option params [String] :secret_access_key required at present, change to allow look up from environment using standard aws sdk routines?
    #
    # @option params [boolean] :default_public (true) default value of `public` when instance method #url is called.
    #
    # @option params [boolean] :cache_signing_keys (false). If set to true, up to five signing keys used for presigned URLs will
    #   be cached and re-used, improving performance when generating mulitple presigned urls with a single Builder by around 50%.
    #   NOTE WELL: This will make the Builder no longer technically concurrency-safe for sharing between multiple threads, is one
    #   reason it is not on by default.
    def initialize(bucket_name:, region:, access_key_id:, secret_access_key:, session_token:nil, host:nil, endpoint: nil, default_public: true, cache_signing_keys: false)
      if endpoint && host
        raise ArgumentError.new("`endpoint` and `host` are mutually exclusive, you can only provide one. You provided endpoint: #{endpoint.inspect} and host: #{host.inspect}")
      end

      @bucket_name = bucket_name
      @region = region

      parsed_uri = parsed_base_uri(bucket_name: bucket_name, host: host, endpoint: endpoint)
      @base_url = URI.join(parsed_uri, "/").to_s.chomp("/") # without path
      @base_path = parsed_uri.path # path component of base url, usually empty
      @host = parsed_uri.host
      @canonical_headers = "host:#{parsed_uri.port == parsed_uri.default_port ? @host : "#{parsed_uri.host}:#{parsed_uri.port}"}\n"

      @default_public = default_public
      @access_key_id = access_key_id
      @secret_access_key = secret_access_key
      @cache_signing_keys = cache_signing_keys
      @session_token = session_token
      if @cache_signing_keys
        @signing_key_cache = {}
      end
    end

    def public_url(key)
      "#{self.base_url}#{self.base_path}/#{uri_escape_key(key)}"
    end

    # Generates a presigned GET URL for a specified S3 object key.
    #
    # @param [String] key The S3 key to create a URL pointing to.
    #
    # @option params [Time] :time (Time.now) The starting time for when the
    #   presigned url becomes active.
    #
    # @option params [String] :response_cache_control
    #   Adds a `response-cache-control` query param to set the `Cache-Control` header of the subsequent response from S3.
    #
    # @option params [String] :response_content_disposition
    #   Adds a `response-content-disposition` query param to set the `Content-Disposition` header of the subsequent response from S3
    #
    # @option params [String] :response_content_encoding
    #   Adds a `response-content-encoding` query param to set `Content-Encoding` header of the subsequent response from S3
    #
    # @option params [String] :response_content_language
    #   Adds a `response-content-language` query param to sets the `Content-Language` header of the subsequent response from S3
    #
    # @option params [String] :response_content_type
    #   Adds a `response-content-type` query param to sets the `Content-Type` header of the subsequent response from S3
    #
    # @option params [String] :response_expires
    #   Adds a `response-expires` query param to sets the `Expires` header of of the subsequent response from S3
    #
    # @option params [String] :version_id
    #   Adds a `versionId` query param to reference a specific version of the object from S3.
    def presigned_url(key, time: nil, expires_in: DEFAULT_EXPIRES_IN,
                        response_cache_control: nil,
                        response_content_disposition: nil,
                        response_content_encoding: nil,
                        response_content_language: nil,
                        response_content_type: nil,
                        response_expires: nil,
                        version_id: nil)
      validate_expires_in(expires_in)

      canonical_uri = self.base_path + "/" + uri_escape_key(key)

      now = time ? time.dup.utc : Time.now.utc # Uh Time#utc is mutating, not nice to do to an argument!
      amz_date  = now.strftime("%Y%m%dT%H%M%SZ")
      datestamp = now.strftime("%Y%m%d")

      credential_scope = datestamp + '/' + region + '/' + SERVICE + '/' + 'aws4_request'

      # These have to be sorted, but sort is case-sensitive, and we have a fixed
      # list of headers we know might be here... turns out they are already sorted?
      canonical_query_params = {
        "X-Amz-Algorithm": ALGORITHM,
        "X-Amz-Credential": uri_escape(@access_key_id + "/" + credential_scope),
        "X-Amz-Date": amz_date,
        "X-Amz-Expires": expires_in.to_s,
        "X-Amz-Security-Token": uri_escape(session_token),
        "X-Amz-SignedHeaders": SIGNED_HEADERS,
        "response-cache-control": uri_escape(response_cache_control),
        "response-content-disposition": uri_escape(response_content_disposition),
        "response-content-encoding": uri_escape(response_content_encoding),
        "response-content-language": uri_escape(response_content_language),
        "response-content-type": uri_escape(response_content_type),
        "response-expires": uri_escape(convert_for_timestamp_shape(response_expires)),
        "versionId": uri_escape(version_id)
      }.compact

      canonical_query_string = canonical_query_params.collect {|k, v| "#{k}=#{v}" }.join("&")

      canonical_request = ["GET",
        canonical_uri,
        canonical_query_string,
        @canonical_headers,
        SIGNED_HEADERS,
        'UNSIGNED-PAYLOAD'
      ].join("\n")

      string_to_sign = [
        ALGORITHM,
        amz_date,
        credential_scope,
        Digest::SHA256.hexdigest(canonical_request)
      ].join("\n")

      signing_key = retrieve_signing_key(datestamp)
      signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, string_to_sign)

      return "#{base_url}#{canonical_uri}?#{canonical_query_string}&X-Amz-Signature=#{signature}"
    end

    # just a convenience method that can call public_url or presigned_url based on flag
    #
    #    signer.url(object_key, public: true)
    #      #=> forwards to signer.public_url(object_key)
    #
    #    signer.url(object_key, public: false, response_content_type: "image/jpeg")
    #       #=> forwards to signer.presigned_url(object_key, response_content_type: "image/jpeg")
    #
    #  Options (sucn as response_content_type) that are not applicable to #public_url
    #  are ignored in public mode.
    #
    #  The default value of `public` can be set by initializer arg `default_public`, which
    #  is itself default true.
    #
    #      builder = FasterS3Url::Builder.new(..., default_public: false)
    #      builder.url(object_key) # will call #presigned_url
    def url(key, public: @default_public, **options)
      if public
        public_url(key)
      else
        presigned_url(key, **options)
      end
    end


    private

    def make_signing_key(datestamp)
      aws_get_signature_key(@secret_access_key, datestamp, @region, SERVICE)
    end

    # If caching of signing keys is turned on, use and cache signing key, while
    # making sure not to cache more than MAX_CACHED_SIGNING_KEYS
    #
    # Otherwise if caching of signing keys is not turned on, just generate and return
    # a signing key.
    def retrieve_signing_key(datestamp)
      if @cache_signing_keys
        if value = @signing_key_cache[datestamp]
          value
        else
          value = @signing_key_cache[datestamp] =  make_signing_key(datestamp)
          while @signing_key_cache.size > MAX_CACHED_SIGNING_KEYS
            @signing_key_cache.delete(@signing_key_cache.keys.first)
          end
          value
        end
      else
        make_signing_key(datestamp)
      end
    end


    # CGI.escapeURIComponent has correct semantics for what AWS wants, and is
    # implemented in C, so pretty fast.
    def uri_escape(string)
      if string.nil?
        nil
      else
        CGI.escapeURIComponent(string.encode('UTF-8'))
      end
    end

    # like uri_escape but does NOT escape `/`, leaves it alone. The appropriate
    # escaping algorithm for an S3 key turning into a URL.
    #
    # Using CGI.escapeURIComponent with a gsub is faster than anything else
    # we found to get this semantics.
    def uri_escape_key(string)
      if string.nil?
        nil
      else
        CGI.escapeURIComponent(string.encode('UTF-8')).tap do |s|
          s.gsub!('%2F'.freeze, '/'.freeze)
        end
      end
    end

    # Handle endpoint, modifying host or path with bucketname, and setting
    # host.
    #
    # if none set, set default host.
    #
    # Set base_url correct for host or endpoint.
    def parsed_base_uri(bucket_name:, host:, endpoint:)
      if host
        return URI.parse("https://#{host}")
      elsif endpoint
        parsed = URI.parse(endpoint)
        if parsed.host =~ /\A\d+\.\d+\.\d+\.\d+\Z/
          parsed.path = "/#{bucket_name}"
        else
          parsed.host = "#{bucket_name}.#{parsed.host}"
        end
        return parsed
      else
        return URI.parse("https://#{default_host(bucket_name)}")
      end
    end

    def default_host(bucket_name)
      if region == "us-east-1"
        # use legacy one without region, as S3 seems to
        "#{bucket_name}.s3.amazonaws.com".freeze
      else
        "#{bucket_name}.s3.#{region}.amazonaws.com".freeze
      end
    end

    # `def get_signature_key` `from python example at https://docs.aws.amazon.com/general/latest/gr/sigv4-signed-request-examples.html
    def aws_get_signature_key(key, date_stamp, region_name, service_name)
      k_date = aws_sign("AWS4" + key, date_stamp)
      k_region = aws_sign(k_date, region_name)
      k_service = aws_sign(k_region, service_name)
      aws_sign(k_service, "aws4_request")
    end

    # `def sign` from python example at https://docs.aws.amazon.com/general/latest/gr/sigv4-signed-request-examples.html
    def aws_sign(key, data)
      OpenSSL::HMAC.digest("SHA256", key, data)
    end

    def validate_expires_in(expires_in)
      if expires_in > ONE_WEEK
        raise ArgumentError.new("expires_in value of #{expires_in} exceeds one-week (#{ONE_WEEK}) maximum.")
      elsif expires_in <= 0
        raise ArgumentError.new("expires_in value of #{expires_in} cannot be 0 or less.")
      end
    end

    # Crazy kind of reverse engineered from aws-sdk-ruby,
    # for compatible handling of Expires header.
    #
    # Recent versions of ruby AWS SDK use "httpdate" format here, as a result of
    # an issue we filed: https://github.com/aws/aws-sdk-ruby/issues/2415
    #
    # We match what recent AWS SDK does.
    #
    # Note while the AWS SDK source says "rfc 822", it's ruby #httpdate that matches
    # rather than ruby #rfc822 (timezone should be `GMT` to match AWS SDK, not `-0000`)
    def convert_for_timestamp_shape(arg)
      return nil if arg.nil?

      time_value = case arg
        when Time
          arg
        when Date, DateTime
          arg.to_time
        when Integer, Float
          Time.at(arg)
        else
          Time.parse(arg.to_s)
      end
      time_value.utc.httpdate
    end
  end
end
