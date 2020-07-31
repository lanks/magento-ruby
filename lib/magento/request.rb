# frozen_string_literal: true

require 'uri'
require 'http'

module Magento
  class Request
    class << self
      def get(resource)
        save_request(:get, url(resource))
        handle_error http_auth.get(url(resource))
      end

      def put(resource, body)
        save_request(:put, url(resource), body)
        handle_error http_auth.put(url(resource), json: body)
      end

      def post(resource, body = nil, url_completa = false)
        url = url_completa ? resource : url(resource)
        save_request(:post, url, body)
        handle_error http_auth.post(url, json: body)
      end

      private

      def http_auth
        HTTP.auth("Bearer #{Magento.token}")
      end

      def base_url
        url = Magento.url.to_s.sub(%r{/$}, '')
        "#{url}/rest/all/V1"
      end

      def url(resource)
        "#{base_url}/#{resource}"
      end

      def parametros_de_busca(field:, value:, conditionType: :eq)
        criar_parametros(
          filter_groups: {
            '0': {
              filters: {
                '0': {
                  field: field,
                  conditionType: conditionType,
                  value: value
                }
              }
            }
          }
        )
      end

      def parametros_de_campos(campos:)
        criar_parametros(fields: campos)
      end

      def criar_parametros(filter_groups: nil, fields: nil, current_page: 1)
        CGI.unescape(
          {
            searchCriteria: {
              currentPage: current_page,
              filterGroups: filter_groups
            }.compact,
            fields: fields
          }.compact.to_query
        )
      end

      def handle_error(resposta)
        unless resposta.status.success?
          errors = []
          begin
            msg = resposta.parse['message']
            errors = resposta.parse['errors']
          rescue StandardError
            msg = resposta.to_s
          end
          raise Magento::NotFound.new(msg, resposta.status.code, errors, @request) if resposta.status.not_found?

          raise Magento::MagentoError.new(msg, resposta.status.code, errors, @request)
        end
        resposta
      end

      def save_request(method, url, body = nil)
        begin
          body = body[:product].reject { |e| e == :media_gallery_entries }
        rescue StandardError
        end

        @request = { method: method, url: url, body: body }
      end
    end
  end
end
