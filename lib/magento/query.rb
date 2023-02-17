# frozen_string_literal: true

require 'cgi'

module Magento
  class Query
    ACCEPTED_CONDITIONS = [
      'eq',      # Equals.
      'finset',  # A value within a set of values
      'from',    # The beginning of a range. Must be used with to
      'gt',      # Greater than
      'gteq',    # Greater than or equal
      'in',      # In. The value can contain a comma-separated list of values.
      'like',    # Like. The value can contain the SQL wildcard characters when like is specified.
      'lt',      # Less than
      'lteq',    # Less than or equal
      'moreq',   # More or equal
      'neq',     # Not equal
      'nfinset', # A value that is not within a set of values
      'nin',     # Not in. The value can contain a comma-separated list of values.
      'notnull', # Not null
      'null',    # Null
      'to'       # The end of a range. Must be used with from
    ].freeze

    def initialize(model, request: Request.new, api_resource: nil)
      @model = model
      @request = request
      @filter_groups = nil
      @current_page = 1
      @page_size = 50
      @sort_orders = nil
      @fields = nil
      @endpoint = api_resource || model.api_resource
    end

    def where(attributes)
      self.filter_groups = [] unless filter_groups
      filters = []
      attributes.each do |key, value|
        field, condition = parse_filter(key)
        value = parse_value_filter(condition, value)
        filters << { field: field, conditionType: condition, value: value }
      end
      filter_groups << { filters: filters }
      self
    end

    def page(current_page)
      self.current_page = current_page
      self
    end

    def page_size(page_size)
      @page_size = page_size
      self
    end

    alias_method :per, :page_size

    def select(*fields)
      fields = fields.map { |field| parse_field(field, root: true) }

      if model == Magento::Category
        self.fields = "children_data[#{fields.join(',')}]"
      else
        self.fields = "items[#{fields.join(',')}],search_criteria,total_count"
      end

      self
    end

    def order(*attributes)
      self.sort_orders = []
      attributes.each do |sort_order|
        if sort_order.is_a?(String) || sort_order.is_a?(Symbol)
          sort_orders << { field: verify_id(sort_order), direction: :asc }
        elsif sort_order.is_a?(Hash)
          sort_order.each do |field, direction|
            raise "Invalid sort order direction '#{direction}'" unless %w[asc desc].include?(direction.to_s)

            sort_orders << { field: verify_id(field), direction: direction }
          end
        end
      end
      self
    end

    def all
      result = JSON.parse(request.get("#{endpoint}?#{query_params}"))
      if model == Magento::Category
        model.build(result)
      else
        RecordCollection.from_magento_response(result, model: model)
      end
    end

    #
    # Loop all products on each page, starting from the first to the last page
    def find_each
      if @model == Magento::Category
        raise NoMethodError, 'undefined method `find_each` for Magento::Category'
      end

      @current_page = 1

      loop do
        redords = all

        redords.each do |record|
          yield record
        end

        break if redords.last_page?

        @current_page = redords.next_page
      end
    end

    def first
      page_size(1).page(1).all.first
    end

    def find_by(attributes)
      where(attributes).first
    end

    def count
      select(:id).page_size(1).page(1).all.total_count
    end

    private

    attr_accessor :current_page, :filter_groups, :request, :sort_orders, :model, :fields

    def endpoint
      @endpoint
    end

    def verify_id(field)
      return model.primary_key if (field.to_s == 'id') && (field.to_s != model.primary_key.to_s)

      field
    end

    def query_params
      query = {
        searchCriteria: {
          filterGroups: filter_groups,
          currentPage: current_page,
          sortOrders: sort_orders,
          pageSize: @page_size
        }.compact,
        fields: fields
      }.compact

      encode query
    end

    def parse_filter(key)
      patter = /(.*)_([a-z]+)$/
      match = key.match(patter)

      return match.to_a[1..2] if match && ACCEPTED_CONDITIONS.include?(match[2])

      [key, 'eq']
    end

    def parse_value_filter(condition, value)
      if ['in', 'nin'].include?(condition) && value.is_a?(Array)
        value = value.join(',')
      end

      value
    end

    def parse_field(value, root: false)
      return (root ? verify_id(value) : value) unless value.is_a? Hash

      value.map do |k, v|
        fields = v.is_a?(Array) ? v.map { |field| parse_field(field) } : [parse_field(v)]
        "#{k}[#{fields.join(',')}]"
      end.join(',')
    end

    def encode(value, key = nil)
      case value
      when Hash  then value.map { |k, v| encode(v, append_key(key, k)) }.join('&')
      when Array then value.each_with_index.map { |v, i| encode(v, "#{key}[#{i}]") }.join('&')
      when nil   then ''
      else
        "#{key}=#{CGI.escape(value.to_s)}"
      end
    end

    def append_key(root_key, key)
      root_key.nil? ? key : "#{root_key}[#{key}]"
    end
  end
end
