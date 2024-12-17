module LinkedData
  module Models
    class Contact < LinkedData::Models::Base
      model :contact, name_with: lambda { |c| uuid_uri_generator(c) }
      attribute :name, enforce: [:existence]
      attribute :email, enforce: [:existence]

      embedded true

      def embedded_doc
        bring(:name) if bring?(:name)
        bring(:email) if bring?(:email)

        "#{self.name} | #{self.email}"
      end

    end
  end
end
