require "ontologies_linked_data/models/users/user"
require "ontologies_linked_data/models/ontology_submission"

module LinkedData
  module Models

    class IdentifierRequestType
      DOI_CREATE = "DOI_CREATE"
      DOI_UPDATE = "DOI_UPDATE"
    end

    class IdentifierRequestStatus
      PENDING = "PENDING"
      SATISFIED = "SATISFIED"
      CANCELED = "CANCELED"
      REJECTED = "REJECTED"
      ERROR = "ERROR"
    end

    class IdentifierRequest < LinkedData::Models::Base
      # ECOPORTAL_LOGGER.debug("\n\n\nONTOLOGIES_LINKED_DATA: identifier_request.rb")
      model :identifier_request, :name_with => :requestId
      
      attribute :requestId, enforce: [:unique, :existence]
      attribute :status, enforce: [:existence] #[PENDING, SATISFIED, CANCELED, REJECTED, ERROR]   
      attribute :requestType, enforce: [:existence]  #[DOI_CREATE, DOI_UPDATE]
      attribute :requestedBy, enforce: [:existence, :user]
      attribute :requestDate, enforce: [:existence, :date_time]
      attribute :processedBy, enforce: [:user]
      attribute :processingDate, enforce: [:date_time]
      attribute :message
      attribute :submission, enforce: [:ontology_submission]
      link_to LinkedData::Hypermedia::Link.new("requestedBy", lambda {|r| "identifier_requests/#{r.requestId}/requestedBy"}, LinkedData::Models::User.uri_type),
              LinkedData::Hypermedia::Link.new("processedBy", lambda {|r| "identifier_requests/#{r.requestId}/processedBy"}, LinkedData::Models::User.uri_type),
              LinkedData::Hypermedia::Link.new("submission", lambda {|r| "identifier_requests/#{r.requestId}/submission"}, LinkedData::Models::OntologySubmission.uri_type)

      # Access control
      read_restriction_based_on lambda {|req| req.submission.ontology}
      access_control_load submission: [ontology: [:administeredBy, :acl, :viewingRestriction]]
      write_access submission: [ontology: [:administeredBy]]
      #access_control_load submission: [:access_control_load_attrs]

      def self.identifierRequest_id_generator()
        millis = Time.now.strftime('%s%3N')
        return millis     
      end
   
    end


    

  end
end
