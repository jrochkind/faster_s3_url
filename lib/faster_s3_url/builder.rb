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

    EMPTY_STRING_HASHED = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855".freeze

    QUERY_STRING_TEMPLATE = [
      "X-Amz-Algorithm=#{ALGORITHM}",
      "X-Amz-SignedHeaders=#{SIGNED_HEADERS}"
    ]

    attr_reader :bucket_name, :region, :host

    def initialize(bucket_name:, region:, host:nil, default_public: true)
      @bucket_name = bucket_name
      @region = region
      @host = host || default_host(bucket_name)
      @default_public = default_public
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

    def presigned_url(key, now: Time.now, **query_params)
      signed_headers = "host;x-amz-date"

      canonical_uri = "/" + uri_escape_key(key)

      now = now.utc
      amz_date  = now.strftime("%Y%m%dT%H%M%SZ")
      datestamp = now.strftime("%Y%m%d")

      credential_scope = datestamp + '/' + region + '/' + 's3' + '/' + 'aws4_request'

      canonical_query_string = [
          "X-Amz-Algorithm=#{ALGORITHM}",
          "X-Amz-Credential=" + CGI.escape(access_key + "/" + credential_scope),
          "X-Amz-Date=" + amz_date,
          "X-Amz-Expires=%d" % @expires_in,
          # ------- When using STS we also need to add the security token
          ("X-Amz-Security-Token=" + CGI.escape(@session_token) if @session_token),
          "X-Amz-SignedHeaders=" + signed_headers,
        ]

      canonical_headers = "host:" + host

      canonical_request = "GET\n" +
        canonical_uri + "\n" +
        canonical_query_string + "\n" +
        canonical_headers + "\n" +
        signed_headers + "\n" +
        EMPTY_STRING_HASH


      string_to_sign =
        ALGORITHM + '\n' +
        amz_date + '\n' +
        credential_scope + '\n' +
        Digest::SHA256.hexdigest(canonical_request)

      signing_key = aws_get_signature_key(aws_secret_key, datestamp, region, "s3")
      signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, string_to_sign)

      return "https://" + self.host + canonical_uri + "?" + "&X-Amz-Signature=" + signature
    end

    private

    TO_ESCAPE_LEAVE_SLASH    = /([^a-zA-Z0-9_.\-\~\/]+)/
    TO_ESCAPE_ALSO_SLASH = /([^a-zA-Z0-9_.\-\~]+)/

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
      k_service = hmac_bytes(k_region, service_name)
      aws_sign(k_service, "aws4_request")
    end

    # `def sign` from python example at https://docs.aws.amazon.com/general/latest/gr/sigv4-signed-request-examples.html
    def aws_sign(key, data)
      OpenSSL::HMAC.digest("SHA256", key, data)
    end

  end
end
