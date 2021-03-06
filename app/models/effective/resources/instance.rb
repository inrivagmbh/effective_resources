module Effective
  module Resources
    module Instance
      attr_accessor :instance

      # This is written for use by effective_logging and effective_trash

      def instance
        @instance || klass.new
      end

      # called by effective_trash and effective_logging
      def instance_attributes(include_associated: true, include_nested: true)
        return {} unless instance.present?

        attributes = { attributes: instance.attributes }

        # Collect to_s representations of all belongs_to associations
        if include_associated
          belong_tos.each do |association|
            attributes[association.name] = instance.send(association.name).to_s
          end
        end

        if include_associated || include_nested
          nested_resources.each do |association|
            attributes[association.name] ||= {}

            next if association.options[:through]

            Array(instance.send(association.name)).each_with_index do |child, index|
              resource = Effective::Resource.new(child)
              attributes[association.name][index] = resource.instance_attributes(include_associated: include_associated, include_nested: include_nested)
            end
          end
        end

        if include_associated
          has_ones.each do |association|
            attributes[association.name] = instance.send(association.name).to_s
          end

          has_manys.each do |association|
            attributes[association.name] = instance.send(association.name).map { |obj| obj.to_s }
          end

          has_and_belongs_to_manys.each do |association|
            attributes[association.name] = instance.send(association.name).map { |obj| obj.to_s }
          end
        end

        attributes.delete_if { |_, value| value.blank? }
      end

      # used by effective_logging
      def instance_changes
        return {} unless (instance.present? && instance.changes.present?)

        changes = instance.changes.delete_if do |attribute, (before, after)|
          begin
            (before.kind_of?(ActiveSupport::TimeWithZone) && after.kind_of?(ActiveSupport::TimeWithZone) && before.to_i == after.to_i) ||
            (before == nil && after == false) || (before == nil && after == ''.freeze)
          rescue => e
            true
          end
        end

        # Log to_s changes on all belongs_to associations
        belong_tos.each do |association|
          if (change = changes.delete(association.foreign_key)).present?
            changes[association.name] = [(association.klass.find_by_id(change.first) if changes.first), instance.send(association.name)]
          end
        end

        changes
      end

    end
  end
end




