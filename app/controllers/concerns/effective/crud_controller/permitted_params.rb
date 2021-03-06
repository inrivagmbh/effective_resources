module Effective
  module CrudController
    module PermittedParams
      BLACKLIST = [:created_at, :updated_at]

      # This is only available to models that use the effective_resource do ... end attributes block
      # It will be called last, and only for those resources
      # params.require(effective_resource.name).permit!
      def resource_permitted_params
        raise 'expected resource class to have effective_resource do .. end' if effective_resource.model.blank?

        permitted_params = permitted_params_for(resource)

        if Rails.env.development?
          Rails.logger.info "Effective::CrudController#resource_permitted_params:"
          Rails.logger.info "params.require(:#{effective_resource.name}).permit(#{permitted_params.to_s[1...-1]})"
        end

        params.require(effective_resource.name).permit(*permitted_params)
      end

      private

      def permitted_params_for(resource)
        effective_resource = if resource.kind_of?(Class)
          resource.effective_resource if resource.respond_to?(:effective_resource)
        else
          resource.class.effective_resource if resource.class.respond_to?(:effective_resource)
        end

        # That class doesn't implement effective_resource do .. end block
        return [] unless effective_resource.present?

        # This is :id, all belongs_to ids, and model attributes
        permitted_params = effective_resource.permitted_attributes.select do |name, (_, atts)|
          if BLACKLIST.include?(name)
            false
          elsif atts.blank? || !atts.key?(:permitted)
            true # Default is true
          else
            permitted = (atts[:permitted].respond_to?(:call) ? instance_exec(&atts[:permitted]) : atts[:permitted])

            if permitted == true || permitted == false
              permitted
            elsif permitted == nil || permitted == :blank
              effective_resource.namespaces.length == 0
            else # A symbol, string, or array of, representing the namespace
              (effective_resource.namespaces & Array(permitted).map(&:to_s)).present?
            end
          end
        end

        permitted_params = permitted_params.map do |k, (datatype, v)|
          if datatype == :array
            { k => [] }
          elsif datatype == :permitted_param && k.to_s.ends_with?('_ids')
            { k => [] }
          elsif datatype == :effective_address
            { k => EffectiveAddresses.permitted_params }
          else
            k
          end
        end

        # Recursively add any accepts_nested_resources
        effective_resource.nested_resources.each do |nested|
          if (nested_params = permitted_params_for(nested.klass)).present?
            nested_params.insert(nested_params.rindex { |obj| !obj.kind_of?(Hash)} + 1, :_destroy)
            permitted_params << { "#{nested.plural_name}_attributes".to_sym => nested_params }
          end
        end

        permitted_params
      end

    end
  end
end
