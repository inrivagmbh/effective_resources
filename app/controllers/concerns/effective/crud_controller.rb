module Effective
  module CrudController
    extend ActiveSupport::Concern

    included do
    end

    module ClassMethods
      # Add the following to your controller for a simple member action
      # member_action :print
      def member_action(action)
        define_method(action) do
          self.resource ||= resource_class.find(params[:id])

          EffectiveResources.authorized?(self, action, resource)

          if (request.post? || request.patch? || request.put?)
            raise "expected @#{resource_name} to respond to #{action}!" unless resource.respond_to?("#{action}!")

            begin
              resource.send("#{action}!") || raise('exception')

              flash[:success] = "Successfully #{action}#{action.to_s.end_with?('e') ? 'd' : 'ed'} #{resource_human_name}"
              redirect_back fallback_location: resource_redirect_path
            rescue => e
              flash.now[:danger] = "Unable to #{action} #{resource_human_name}: #{resource.errors.full_messages.to_sentence.presence || e.message}"

              referer = request.referer.to_s

              if referer.end_with?(send(effective_resource.edit_path, resource))
                @page_title ||= "Edit #{resource}"
                render :edit
              elsif referer.end_with?(send(effective_resource.new_path))
                @page_title ||= "New #{resource_name.titleize}"
                render :new
              else
                @page_title ||= resource.to_s
                flash[:danger] = flash.now[:danger]

                if referer.present? && (Rails.application.routes.recognize_path(URI(referer).path) rescue false)
                  redirect_back fallback_location: resource_redirect_path
                else
                  redirect_to(resource_redirect_path)
                end
              end
            end
          end
        end
      end

    end

    def index
      @page_title ||= resource_plural_name.titleize
      EffectiveResources.authorized?(self, :index, resource_class.new)

      self.resources ||= resource_class.all

      if resource_datatable_class
        @datatable ||= resource_datatable_class.new(self, resource_datatable_attributes)
      end
    end

    def new
      self.resource ||= resource_class.new

      self.resource.assign_attributes(
        params.to_unsafe_h.except(:controller, :action).select { |k, v| resource.respond_to?("#{k}=") }
      )

      @page_title ||= "New #{resource_name.titleize}"
      EffectiveResources.authorized?(self, :new, resource)
    end

    def create
      self.resource ||= resource_class.new(send(resource_params_method_name))

      @page_title ||= "New #{resource_name.titleize}"
      EffectiveResources.authorized?(self, :create, resource)

      resource.created_by ||= current_user if resource.respond_to?(:created_by=)

      if resource.save
        flash[:success] = "Successfully created #{resource_human_name}"
        redirect_to(resource_redirect_path)
      else
        flash.now[:danger] = "Unable to create #{resource_human_name}: #{resource.errors.full_messages.to_sentence}"
        render :new
      end
    end

    def show
      self.resource ||= resource_class.find(params[:id])

      @page_title ||= resource.to_s
      EffectiveResources.authorized?(self, :show, resource)
    end

    def edit
      self.resource ||= resource_class.find(params[:id])

      @page_title ||= "Edit #{resource}"
      EffectiveResources.authorized?(self, :edit, resource)
    end

    def update
      self.resource ||= resource_class.find(params[:id])

      @page_title = "Edit #{resource}"
      EffectiveResources.authorized?(self, :update, resource)

      if resource.update_attributes(send(resource_params_method_name))
        flash[:success] = "Successfully updated #{resource_human_name}"
        redirect_to(resource_redirect_path)
      else
        flash.now[:danger] = "Unable to update #{resource_human_name}: #{resource.errors.full_messages.to_sentence}"
        render :edit
      end
    end

    def destroy
      self.resource = resource_class.find(params[:id])

      @page_title = "Destroy #{resource}"
      EffectiveResources.authorized?(self, :destroy, resource)

      if resource.destroy
        flash[:success] = "Successfully deleted #{resource_human_name}"
      else
        flash[:danger] = "Unable to delete #{resource_human_name}: #{resource.errors.full_messages.to_sentence}"
      end

      if request.referer.present? && !request.referer.include?(send(effective_resource.show_path))
        redirect_to(request.referer)
      else
        redirect_to(send(resource_index_path))
      end

    end

    protected

    def resource_redirect_path
      case params[:commit].to_s
      when 'Save'               ; send(effective_resource.edit_path, resource)
      when 'Save and Continue'  ; send(effective_resource.index_path)
      when 'Save and Add New'   ; send(effective_resource.new_path)
      when 'Save and Return'
        request.referer.present? ? request.referer : send(resource_index_path)
      else
        send((effective_resource.show_path(check: true) || effective_resource.edit_path), resource)
      end
    end

    def resource # @thing
      instance_variable_get("@#{resource_name}")
    end

    def resource=(instance)
      instance_variable_set("@#{resource_name}", instance)
    end

    def resources # @things
      send(:instance_variable_get, "@#{resource_plural_name}")
    end

    def resources=(instance)
      send(:instance_variable_set, "@#{resource_plural_name}", instance)
    end

    private

    def effective_resource
      @_effective_resource ||= Effective::Resource.new(controller_path)
    end

    def resource_name # 'thing'
      effective_resource.name
    end

    def resource_human_name
      effective_resource.human_name
    end

    def resource_plural_name # 'things'
      effective_resource.plural_name
    end

    # Scoped to resource_scope_method_name
    def resource_class # Thing
      @resource_class ||= (
        if resource_scope_method_name.blank?
          effective_resource.klass
        else
          case (resource_scope = send(resource_scope_method_name))
          when ActiveRecord::Relation
            effective_resource.relation.merge(resource_scope)
          when Hash
            effective_resource.klass.where(resource_scope)
          when Symbol
            effective_resource.klass.send(resource_scope)
          when nil
            effective_resource.klass
          else
            raise "expected #{resource_scope_method_name} to return a Hash or Symbol"
          end
        end
      )
    end

    def resource_datatable_attributes
      return {} unless resource_scope_method_name.present?

      case (resource_scope = send(resource_scope_method_name))
      when ActiveRecord::Relation ; {resource_scope: true}
      when Hash   ; resource_scope
      when Symbol ; {resource_scope: true}
      when nil    ; {}
      else
        raise "expected #{resource_scope_method_name} to return a Hash or Symbol"
      end
    end

    def resource_datatable_class # ThingsDatatable
      effective_resource.datatable_klass
    end

    def resource_params_method_name
      ["#{resource_name}_params", "#{resource_plural_name}_params", 'permitted_params'].find { |name| respond_to?(name, true) } || 'params'
    end

    def resource_scope_method_name
      ["#{resource_name}_scope", "#{resource_plural_name}_scope", 'resource_scope', 'default_scope'].find { |name| respond_to?(name, true) }
    end

    def resource_index_path
      effective_resource.index_path
    end

  end
end
