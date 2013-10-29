require 'pony'

module LinkedData::Utils
  class Notifications

    def self.notify(options = {})
      return unless LinkedData.settings.enable_notifications

      headers    = { 'Content-Type' => 'text/html' }
      sender     = options[:sender] || LinkedData.settings.email_sender
      recipients = options[:recipients]
      raise ArgumentError, "Recipient needs to be provided in options[:recipients]" if !recipients || recipients.empty?

      # By default we override all recipients to avoid
      # sending emails from testing environments.
      # Set `email_disable_override` in production
      # to send to the actual user.
      unless LinkedData.settings.email_disable_override
        headers['Overridden-Sender'] = recipients
        recipients = LinkedData.settings.email_override
      end

      Pony.mail({
        to: recipients,
        from: sender,
        subject: options[:subject],
        body: options[:body],
        headers: headers,
        via: :smtp,
        via_options: mail_options
      })
    end

    def self.new_note(note)
      note.bring_remaining
      note.creator.bring(:username) if note.creator.bring?(:username)
      note.relatedOntology.each {|o| o.bring(:name) if o.bring?(:name); o.bring(:subscriptions) if o.bring?(:subscriptions)}
      ontologies = note.relatedOntology.map {|o| o.name}.join(", ")
      subject = "[BioPortal Notes] [#{ontologies}] #{note.subject}"
      body = NEW_NOTE.gsub("%username%", note.creator.username)
                     .gsub("%ontologies%", ontologies)
                     .gsub("%note_url%", LinkedData::Hypermedia.generate_links(note)["ui"])
                     .gsub("%note_subject%", note.subject || "")
                     .gsub("%note_body%", note.body || "")

      options = {
        ontologies: note.relatedOntology,
        notification_type: "NOTES",
        subject: subject,
        body: body
      }
      send_ontology_notifications(options)
    end

    def self.submission_processed(submission)
      submission.bring_remaining
      ontology = submission.ontology
      ontology.bring(:name, :acronym)
      result = submission.ready? ? "Success" : "Failure"
      status = LinkedData::Models::SubmissionStatus.readable_statuses(submission.submissionStatus)

      subject = "[BioPortal] #{ontology.name} Parsing #{result}"
      body = SUBMISSION_PROCESSED.gsub("%ontology_name%", ontology.name)
                                 .gsub("%ontology_acronym%", ontology.acronym)
                                 .gsub("%statuses%", status.join("<br/>"))
                                 .gsub("%admin_email%", LinkedData.settings.email_sender)
                                 .gsub("%ontology_location%", LinkedData::Hypermedia.generate_links(ontology)["ui"])

      options = {
        ontologies: ontology,
        notification_type: "PROCESSING",
        subject: subject,
        body: body
      }
      send_ontology_notifications(options)
    end

    private

    ##
    # This method takes a list of ontologies and a notification type,
    # then looks up all the users who subscribe to that ontology/type pair
    # and sends them an email with the given subject and body.
    def self.send_ontology_notifications(options = {})
      ontologies        = options[:ontologies]
      ontologies        = ontologies.is_a?(Array) ? ontologies : [ontologies]
      notification_type = options[:notification_type]
      subject           = options[:subject]
      body              = options[:body]
      emails            = []
      ontologies.each {|o| o.bring(:subscriptions) if o.bring?(:subscriptions)}
      ontologies.each do |ont|
        ont.subscriptions.each do |subscription|
          subscription.bring(:notification_type) if subscription.bring?(:notification_type)
          subscription.notification_type.bring(:type) if subscription.notification_type.bring?(:notification_type)
          next unless subscription.notification_type.type.eql?(notification_type.to_s.upcase) || subscription.notification_type.type.eql?("ALL")
          subscription.bring(:user) if subscription.bring?(:user)
          subscription.user.each do |user|
            user.bring(:email) if user.bring?(:email)
            emails << notify(recipients: user.email, subject: subject, body: body)
          end
        end
      end
      emails
    end

    def self.mail_options
      options = {
        address: LinkedData.settings.smtp_host,
        port:    LinkedData.settings.smtp_port,
        domain:  LinkedData.settings.smtp_domain # the HELO domain provided by the client to the server
      }

      if LinkedData.settings.smtp_auth_type && LinkedData.settings.smtp_auth_type != :none
        options.merge({
          user_name:      LinkedData.settings.smtp_user,
          password:       LinkedData.settings.smtp_password,
          authentication: LinkedData.settings.smtp_auth_type
        })
      end

      return options
    end

NEW_NOTE = <<EOS
A new note was added to %ontologies% by <b>%username%</b>.<br/><br/>

----------------------------------------------------------------------------------<br/>
<b>Subject:</b> %note_subject%<br/><br/>

%note_body%<br/>
----------------------------------------------------------------------------------<br/><br/>

You can respond by visiting: <a href="%note_url%">NCBO BioPortal</a>.<br/><br/>
EOS

SUBMISSION_PROCESSED = <<EOS
%ontology_name% (%ontology_acronym%) was processed for use in BioPortal. Here are the results:
<br><br>
%statuses%
<br><br>
Please contact %admin_email% if you have questions.
<br><br>
The ontology can be <a href="%ontology_location%">browsed in BioPortal</a>.
<br><br>
Thank you,<br>
The BioPortal Team
EOS

  end
end