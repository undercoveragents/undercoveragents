# frozen_string_literal: true

module Missions
  module CollectionResolver
    private

    def resolve_collection_reference(context, expression, field_name: "collection")
      Missions::ValueResolver.new(context).collection(expression, field_name:)
    end
  end
end
