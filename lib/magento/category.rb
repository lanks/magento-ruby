module Magento
  class Category < Model
    def products
      request.get("categories/#{id}/products").parse
    end
  end
end