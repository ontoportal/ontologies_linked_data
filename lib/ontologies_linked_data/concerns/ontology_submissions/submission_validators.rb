module LinkedData
  module Concerns
    module OntologySubmission
      module Validators

        def enforce_symmetric_ontologies(inst, attr)
          previous_values = inst.previous_values ? Array(inst.previous_values[attr]) : []
          new_values, deleted_values = new_and_deleted_elements(Array(inst.send(attr)), previous_values)
          deleted_values.each do |val|
            update_submission_values(inst, attr, val, action: :remove)
          end
          new_values.each do |val|
            update_submission_values(inst, attr, val)
          end
        end

        def retired_previous_align(inst, attr)
          return unless retired?

          sub = previous_submission
          return if sub.nil?

          sub.bring_remaining
          sub.status = 'retired'
          sub.valid = DateTime.now if sub.valid.nil?
          sub.deprecated = true
          sub.save
        end

        def deprecated_retired_align(inst, attr)
          [:deprecated_retired_align, "can't be with the status retired and not deprecated"] if !deprecated? && retired?
        end

        def deprecate_previous_submissions(inst, attr)
          sub = previous_submission
          return if sub.nil?

          changed = false

          sub.bring_remaining
          unless deprecated?(sub)
            sub.deprecated = true
            changed = true
          end

          unless sub.valid
            inst.bring :modificationDate if inst.bring?(:modificationDate)
            inst.bring :creationDate if inst.bring?(:creationDate)
            sub.valid = inst.modificationDate || inst.creationDate || DateTime.now
            changed = true
          end
          sub.save if changed
        end

        def validity_date_retired_align(inst, attr)
          valid_date = inst.send(attr)

          if deprecated? || retired?
            if valid_date.nil? || (valid_date && valid_date >= DateTime.now)
              [:validity_date_retired_align, "validity date should be before or equal to #{DateTime.now}"]
            end
          elsif valid_date && valid_date <= DateTime.now
            [:validity_date_retired_align,
             "can't be with the status retired  and with validity date should that is before or equal to #{DateTime.now}"]
          end
        end



        private

        def previous_submission
          self.ontology.bring(:submissions) if self.ontology.bring?(:submissions)
          submissions = self.ontology.submissions

          return if submissions.nil?

          submissions.each { |s| s.bring(:submissionId) }
          # Sort submissions in descending order of submissionId, extract last two submissions
          sorted_submissions = submissions.sort { |a, b| b.submissionId <=> a.submissionId }.reverse

          current_index = sorted_submissions.index { |x| x.submissionId.eql?(self.submissionId) }

          if current_index.nil?
            sorted_submissions.last
          else
            min_index = [current_index - 1, 0].max
            sub = sorted_submissions[min_index]
            sub unless sub.submissionId.eql?(self.submissionId)
          end
        end

        def deprecate(inst)
          inst.bring :deprecated if inst.bring?(:deprecated)
          inst.deprecated = true
        end

        def retired?
          self.status.eql?('retired')
        end

        def deprecated?(inst = self)
          inst.bring :deprecated if inst.bring?(:deprecated)
          inst.deprecated
        end

        def new_and_deleted_elements(current_values, previous_values)
          new_elements = current_values - previous_values
          deleted_elements = previous_values - current_values
          [new_elements, deleted_elements]
        end

        def update_submission_values(inst, attr, val, action: :append)

          submission, target_ontologies = target_ontologies(attr, val)

          if action.eql?(:append) && target_ontologies && !target_ontologies.include?(inst.ontology.id)
            target_ontologies << inst.ontology.id
          elsif action.eql?(:remove) && target_ontologies && target_ontologies.include?(inst.ontology.id) # delete
            target_ontologies.delete(inst.ontology.id)
          else
            return
          end
          submission.bring_remaining
          submission.send("#{attr}=", target_ontologies)
          submission.save(callbacks: false) if submission.valid?
        end

        def target_ontologies(attr, val)
          ont = LinkedData::Models::Ontology.find(val).first

          return unless ont

          submission = ont.latest_submission || ont.bring(:submissions) && ont.submissions.last
          return unless submission

          submission.bring(attr) if submission.bring?(attr)

          [submission, Array(submission.send(attr)).dup]
        end

      end

    end
  end
end

