# frozen_string_literal: true

require 'uri'
require 'ipaddr'

module FasterS3Url
  class BaseURI
    def initialize(bucket_name:, region:, endpoint: nil, host: nil)
      @bucket_name = bucket_name
      @region = region
      @endpoint = endpoint
      @host_param = host
    end

    def ip?
      @ip ||= begin
        return false unless uri

        IPAddr.new(uri.host)
        true
      rescue IPAddr::InvalidAddressError
        false
      end
    end

    def scheme
      @scheme ||= uri&.scheme || 'https'
    end

    def host
      @host ||= if endpoint
        ip? ? uri.host : "#{bucket_name}.#{uri.host}"
      elsif host_param
        host_param
      else
        default_host(bucket_name)
      end
    end

    def host_with_port
      [
        host,
        port
      ].compact.join(':')
    end

    private

    attr_reader :bucket_name, :endpoint, :host_param, :region

    def uri
      @uri ||= if endpoint
        URI.parse(endpoint)
      end
    end

    def port
      @port ||= if uri&.port && uri&.default_port != uri&.port
        uri.port
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

  end
end
