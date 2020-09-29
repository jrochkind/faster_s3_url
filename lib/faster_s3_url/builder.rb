# frozen_string_literal: true

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

    attr_reader :bucket_name, :region, :host, :access_key_id

    def initialize(bucket_name:, region:, access_key_id:, secret_access_key:, host:nil, default_public: true)
      @bucket_name = bucket_name
      @region = region
      @host = host || default_host(bucket_name)
      @default_public = default_public
      @access_key_id = access_key_id
      @secret_access_key = secret_access_key
    end

    def url(key, public: default_public, **options)
      if public
        public_url(key)
      else
        prepared_url(key, **options)
      end
    end

    def public_url(key)
      "https://#{self.host}/#{uri_escape_key(key)}"
    end

    def presigned_url(key, now: nil, expires_in: DEFAULT_EXPIRES_IN,
                        response_cache_control: nil,
                        response_content_disposition: nil,
                        response_content_encoding: nil,
                        response_content_language: nil,
                        response_content_type: nil,
                        response_expires: nil,
                        version_id: nil)
      validate_expires_in(expires_in)

      canonical_uri = "/" + uri_escape_key(key)

      now = now ? now.dup.utc : Time.now.utc # Uh Time#utc is mutating, not nice to do to an argument!
      amz_date  = now.strftime("%Y%m%dT%H%M%SZ")
      datestamp = now.strftime("%Y%m%d")

      credential_scope = datestamp + '/' + region + '/' + SERVICE + '/' + 'aws4_request'

      canonical_query_string_parts = [
          "X-Amz-Algorithm=#{ALGORITHM}",
          "X-Amz-Credential=" + uri_escape(@access_key_id + "/" + credential_scope),
          "X-Amz-Date=" + amz_date,
          "X-Amz-Expires=" + expires_in.to_s,
          "X-Amz-SignedHeaders=" + SIGNED_HEADERS,
        ]

      extra_params = {
        :"response-cache-control" => response_cache_control,
        :"response-content-disposition" => response_content_disposition,
        :"response-content-encoding" => response_content_encoding,
        :"response-content-language" => response_content_language,
        :"response-content-type" => response_content_type,
        :"response-expires" => response_expires,
        :"versionId" => version_id
      }.compact

      if extra_params.size > 0
        extra_param_parts = extra_params.collect {|k, v| "#{k}=#{uri_escape v}" }.join("&")
        (canonical_query_string_parts << extra_param_parts).sort!
      end

      canonical_query_string = canonical_query_string_parts.join("&")

      canonical_headers = "host:" + host + "\n"

      canonical_request = "GET\n" +
        canonical_uri + "\n" +
        canonical_query_string + "\n" +
        canonical_headers + "\n" +
        SIGNED_HEADERS + "\n" +
        'UNSIGNED-PAYLOAD'

      string_to_sign =
        ALGORITHM + "\n" +
        amz_date + "\n" +
        credential_scope + "\n" +
        Digest::SHA256.hexdigest(canonical_request)

      signing_key = aws_get_signature_key(@secret_access_key, datestamp, region, SERVICE)
      signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, string_to_sign)

      return "https://" + self.host + canonical_uri + "?" + canonical_query_string + "&X-Amz-Signature=" + signature
    end

    private

    TO_ESCAPE_LEAVE_SLASH = /([^a-zA-Z0-9_.\-\~\/]+)/
    TO_ESCAPE_ALSO_SLASH  = /([^a-zA-Z0-9_.\-\~]+)/

    # Based on CGI.escape source, but changed to match what original S3 public_url
    # code actually needs, but does with inefficient extra gsubs:
    #  * IF escape_slash:true, don't escape '/', leave it alone (used for escaping S3 keys)
    #  * don't escape '~', leave it alone
    #  * escape ' ' to '%2F', not '+;'
    #
    # Code in aws-sdk does this by using CGI.escape and adding 2-3 additional gsub passes
    # on top, much more efficient to do what we need in one go.
    def uri_escape(string, escape_slash: true)
      regexp = escape_slash ? TO_ESCAPE_ALSO_SLASH : TO_ESCAPE_LEAVE_SLASH

      encoding = string.encoding

      string.b.gsub(regexp) do |m|
        '%' + m.unpack('H2' * m.bytesize).join('%').upcase
      end.force_encoding(encoding)
    end

    def uri_escape_key(s3_object_key)
      uri_escape(s3_object_key, escape_slash: false)
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
        raise ArgumentError.new("expires_in value of #{expires_in} exceeds one-week maximum.")
      elsif expires_in <= 0
        raise ArgumentError.new("expires_in value of #{expires_in} cannot be 0 or less.")
      end
    end
  end
end
