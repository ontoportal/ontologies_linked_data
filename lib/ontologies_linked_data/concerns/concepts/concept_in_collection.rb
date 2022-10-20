module LinkedData
  module Concerns
    module Concept
      module InCollection
        def self.included(base)
          base.serialize_methods :isInActiveCollection
        end

        def isInActiveCollection
          @isInActiveCollection
        end

        def inCollection?(collection)
          self.inCollection.include?(collection)
        end

        def load_is_in_collection(collections = [])
          included = collections.select { |s| incollection?(s) }
          @isInActiveCollection = included
        end

      end
    end
  end
end
