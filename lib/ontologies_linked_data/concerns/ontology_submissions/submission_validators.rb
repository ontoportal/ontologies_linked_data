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

        private

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

