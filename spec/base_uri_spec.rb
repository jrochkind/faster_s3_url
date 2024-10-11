require 'spec_helper'

RSpec.describe FasterS3Url::BaseURI do
  let(:bucket_name) { 'my-bucket' }
  let(:region) { 'us-east-1'}
  let(:endpoint) { nil }
  let(:host) { nil }

  let(:subject) do
    described_class.new(
      bucket_name: bucket_name,
      region: region,
      endpoint: endpoint,
      host: host
    )
  end

  describe 'with the endpoint param' do
    describe 'and the endpoint is a string' do
      let(:endpoint) { 'http://example.com' }

      it 'fetches the information for that endpoint' do
        expect(subject.ip?).to eq false
        expect(subject.scheme).to eq 'http'
        expect(subject.host).to eq 'my-bucket.example.com'
        expect(subject.host_with_port).to eq 'my-bucket.example.com'
      end
    end

    describe 'and the endpoint is an ip address' do
      let(:endpoint) { 'http://127.0.0.1:9000' }

      it 'fetches the information for that endpoint' do
        expect(subject.ip?).to eq true
        expect(subject.scheme).to eq 'http'
        expect(subject.host).to eq '127.0.0.1'
        expect(subject.host_with_port).to eq '127.0.0.1:9000'
      end
    end
  end

  describe 'with the host param' do
    describe 'and the endpoint is a string' do
      let(:host) { 'example.com' }

      it 'fetches the information for that endpoint' do
        expect(subject.ip?).to eq false
        expect(subject.scheme).to eq 'https'
        expect(subject.host).to eq 'example.com'
        expect(subject.host_with_port).to eq 'example.com'
      end
    end

    describe 'and an endpoint param' do
      let(:host) { 'example.com' }
      let(:endpoint) { 'http://127.0.0.1:9000' }

      it 'fetches the information for that endpoint, and ignores the host' do
        expect(subject.ip?).to eq true
        expect(subject.scheme).to eq 'http'
        expect(subject.host).to eq '127.0.0.1'
        expect(subject.host_with_port).to eq '127.0.0.1:9000'
      end
    end
  end

end
