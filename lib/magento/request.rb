# frozen_string_literal: true

require 'uri'
require 'http'
require 'oauth'

module Magento
  class Request
    attr_reader :config
    # , :consumer_key, :consumer_secret, :access_token, :token_secret, :website

    def initialize(config: Magento.configuration)
      @config = config
    end

    def get(resource)
      save_request(:get, url(resource))
      handle_error http_auth.get(url(resource))
    end

    def put(resource, body)
      save_request(:put, url(resource), body)
      handle_error http_auth.put(url(resource), body)
    end

    def post(resource, body = nil, url_completa = false)
      url = url_completa ? resource : url(resource)
      save_request(:post, url, body)
      puts "***** BODY *****"
      puts body
      puts "***** URL ***** #{url}"
      handle_error http_auth.post(url, body)
    end

    def delete(resource)
      save_request(:delete, url(resource))
      handle_error http_auth.delete(url(resource))
    end

    private

    def oauth
      @consumer ||= OAuth::Consumer.new(config.consumer_key, config.consumer_secret, {site: config.url, no_verify: true, signature_method: "HMAC-SHA256"})
      @access_token ||= OAuth::AccessToken.new(@consumer, token=config.access_token, secret=config.token_secret)
    end

    def http_auth
      # oauthenticator_signable_request = OAuthenticator::SignableRequest.new(
      #   request_method: "GET",
      #   uri: my_request_uri,
      #   body: "",
      #   media_type: "application/json",
      #   signature_method: "HMAC-SHA256",
      #   consumer_key: "v22hp8vi081pe163ocmx6os4odxsgmix",
      #   consumer_secret: "cpqjogyxb5cqt0eoi59ieej39y53v2pw",
      #   token: "kkw99pyzzgi47o0omxrx6sscpbsfitu2",
      #   token_secret: "wka9gtw3dbcz1qubnndpw7m6b70hillo"
      # )
      # HTTP.auth('OAuth oauth_consumer_key="v22hp8vi081pe163ocmx6os4odxsgmix",oauth_token="kkw99pyzzgi47o0omxrx6sscpbsfitu2",oauth_signature_method="HMAC-SHA256",oauth_timestamp="1676609692",oauth_nonce="Van3GVgmRfi",oauth_version="1.0",oauth_signature="B1JMIpx3NSuBNcgG8kS7f1uzukleUSGPWoCZ9DNNGJA%3D"')
      # # HTTP..headers()
      
      #     .timeout(connect: config.timeout, read: config.open_timeout)
      return oauth
    end

    def base_path
      "rest/#{config.store}/V1"
    end

    def base_url
      url = config.url.to_s.sub(%r{/$}, '')
      "#{url}"
    end

    def url(resource)
      puts "#{base_url}/#{base_path}/#{resource}"
      "#{base_url}/#{base_path}/#{resource}"
    end

    def handle_error(resp)
      return resp.body if ["200"].include?(resp.code)
      puts resp.body
      begin
        msg = resp.parse['message']
        errors = resp.parse['errors'] || resp.parse['parameters']
        case errors
        when Hash
          errors.each { |k, v| msg.sub! "%#{k}", v }
        when Array
          errors.each_with_index { |v, i| msg.sub! "%#{i + 1}", v.to_s }
        end
      rescue StandardError
        msg = 'Failed access to the magento server'
        errors = []
      end

      raise Magento::NotFound.new(msg, resp.code, errors, @request) if resp.code == "404"

      raise Magento::MagentoError.new(msg, resp.code, errors, @request)
    end

    def save_request(method, url, body = nil)
      begin
        body = body.symbolize_keys[:product].reject { |e| e == :media_gallery_entries }
      rescue StandardError
      end

      @request = { method: method, url: url, body: body }
    end
  end
end
