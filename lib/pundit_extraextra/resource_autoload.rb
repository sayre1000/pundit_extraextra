require 'active_support/concern'

module PunditExtraExtra
  module ResourceAutoload
    extend ActiveSupport::Concern

    included do
      class_attribute :resource_options
      self.resource_options = []
      before_action :process_resource_callbacks
    end

    module ClassMethods
      def load_resource(resource_name_or_options = {}, options = {})
        store_resource_options(:load, resource_name_or_options, options)
      end

      def authorize_resource(resource_name_or_options = {}, options = {})
        store_resource_options(:authorize, resource_name_or_options, options)
      end

      def skip_authorization(options = {})
        before_action :skip_authorization_and_scope, options.dup
      end

      def load_and_authorize_resource(resource_name_or_options = {}, options = {})
        store_resource_options(:load_and_authorize, resource_name_or_options, options)
      end

      private
      def store_resource_options(action, resource_name_or_options, options)
        resource_name, options = extract_resource_name_and_options(resource_name_or_options, options)
        self.resource_options += [{ action: action, resource_name: resource_name, options: options }]
      end

      def extract_resource_name_and_options(resource_name_or_options, options)
        if resource_name_or_options.is_a?(Hash)
          [nil, resource_name_or_options]
        elsif resource_name_or_options.is_a?(Symbol) || resource_name_or_options.is_a?(String)
          [resource_name_or_options.to_s, options]
        else
          [nil, options]
        end
      end
    end

    def process_resource_callbacks
      self.class.resource_options.each do |resource_option|
        next if skip_action?(resource_option[:options])

        if resource_option[:action] == :load
          load_resource(resource_option[:resource_name], resource_option[:options])
        elsif resource_option[:action] == :authorize
          authorize_resource(resource_option[:resource_name], resource_option[:options])
        elsif resource_option[:action] == :load_and_authorize
          load_resource(resource_option[:resource_name], resource_option[:options])
          authorize_resource(resource_option[:resource_name], resource_option[:options])
        end
      end
    end

    def skip_action?(options)
      action = params[:action].to_sym
      (options[:except] && Array(options[:except]).include?(action)) ||
        (options[:only] && !Array(options[:only]).include?(action))
    end

    def load_resource(resource_name = nil, options = {})
      resource_name = (resource_name || controller_name.singularize).to_s
      instance_name = options[:instance_name] || resource_name
      scope = resource_name.classify.constantize
      action = params[:action]
      varname = instance_name

      # Use id_param option if provided, otherwise fallback to default pattern
      resource_id_param = options[:id_param] || "#{resource_name}_id"
      resource_id = params[resource_id_param] || params[:id]

      if resource_name != controller_name.singularize
        # If the resource being loaded isn't the primary resource for the controller
        # we assume we are loading a single instance of it

        if options[:through]
          # If there's a through option, find the parent instance
          current_instance = find_parent_instance(options[:through])

          if current_instance
            if options[:singleton]
              # If the relationship is has_one, we load the single associated instance
              resource = current_instance.public_send(resource_name)
            else
              # Otherwise, we find by resource_id or simply the first matching resource
              resource = resource_id ? current_instance.public_send(resource_name.pluralize).find(resource_id) : current_instance.public_send(resource_name.pluralize).first
            end
          else
            resource = nil
          end
        else
          # Load the resource directly if no `through` option or if `resource_id_param` is provided
          resource = scope.find(resource_id)
        end

        raise ActiveRecord::RecordNotFound, "No valid parent instance found through #{options[:through].join(', ')}" if resource == nil

        # Authorize the loaded resource for the 'show' action
        authorize resource, "show?"
      else
        resource = if options[:through]
                     load_through_resource(options[:through], resource_name, resource_id, action, options)
                   else
                     load_direct_resource(scope, action, resource_id, options)
                   end
      end

      raise ActiveRecord::RecordNotFound, "Couldn't find #{resource_name.to_s.capitalize} with #{resource_id_param} == #{resource_id}"if resource.nil?

      if resource.is_a?(ActiveRecord::Relation) || resource.is_a?(Array)
        varname = varname.to_s.pluralize
      end

      instance_variable_set("@#{varname}", resource)
    end

    def find_parent_instance(parents)
      Array(parents).each do |parent|
        parent_resource_name = parent.to_s.singularize
        parent_instance = instance_variable_get("@#{parent_resource_name}")

        return parent_instance if parent_instance
      end

      nil
    end

    def load_singleton_resource(current_instance, resource_name, action, options)
      if action == 'create'
        new_resource = resource_name.classify.constantize.new
        new_resource.attributes = resource_attributes(new_resource, action) if new_resource.respond_to?(:attributes=)
        new_resource
      else
        current_instance.public_send(resource_name)
      end
    end

    def load_index_resource(current_instance, resource_name)
      resource = current_instance.public_send(resource_name.pluralize)
      policy_scope(resource)
    end

    def find_resource_by_id(current_instance, resource_name, resource_id, find_by_attribute)
      current_instance.public_send(resource_name.pluralize).find_by(find_by_attribute => resource_id)
    end

    def create_new_resource(resource_name, action)
      new_resource = resource_name.classify.constantize.new
      new_resource.attributes = resource_attributes(new_resource, action)
      new_resource
    end

    def update_resource(current_instance, resource_name, resource_id, find_by_attribute, action)
      resource = current_instance.public_send(resource_name.pluralize).find_by(find_by_attribute => resource_id)
      unless record.nil?
        authorize resource, "#{action}?"
        resource.attributes = resource_attributes(resource, action) if resource.respond_to?(:attributes=)
      else
        resource = nil
      end

      resource
    end

    def load_nested_resource(parent_instances, resource_name, current_instance)
      if parent_instances.size > 1
        query = parent_instances.inject({}) do |hash, parent_instance|
          association_name = parent_instance.class.name.underscore.to_sym
          hash.merge!(association_name => parent_instance)
        end
        resource_name.classify.constantize.find_by(query)
      else
        current_instance.public_send(resource_name.pluralize)
        policy_scope(resource_name.classify.constantize)
      end
    end

    def load_through_resource(parents, resource_name, resource_id, action, options)
      parent_instances = Array(parents).map do |parent|
        instance_variable_get("@#{parent.to_s.singularize}")
      end.compact

      if parent_instances.empty?
        raise ActiveRecord::RecordNotFound, "No parent instance found for #{resource_name}"
      end

      current_instance = parent_instances.first
      find_by_attribute = options[:find_by] || :id

      resource = if options[:singleton]
                   load_singleton_resource(current_instance, resource_name, action, options)
                 elsif action == 'index' && (!resource_id && !options[:singleton])
                   load_index_resource(current_instance, resource_name)
                 elsif resource_id
                   find_resource_by_id(current_instance, resource_name, resource_id, find_by_attribute)
                 elsif action == 'create'
                   create_new_resource(resource_name, action)
                 elsif action == 'update'
                   update_resource(current_instance, resource_name, resource_id, find_by_attribute, action)
                 else
                   load_nested_resource(parent_instances, resource_name, current_instance)
                 end

      resource
    end

    def load_direct_resource(scope, action, resource_id, options = {})
      # Determine the attribute to find by and the parameter to use for the ID
      # if it isn't specified we assume we're finding by the 'id' column
      find_by_attribute = options[:find_by] || :id

      if action == 'create'
        if resource_id
          resource = scope.find_by(find_by_attribute => resource_id) # Use the custom find_by attribute
        else
          new_resource = scope.new
          new_resource.attributes = resource_attributes(new_resource, action) if new_resource.respond_to?(:attributes=)
          resource = new_resource
        end
      elsif action == 'update'
        resource = scope.find_by(find_by_attribute => resource_id) # Use the custom find_by attribute
        unless resource.nil?
          authorize resource, "#{action}?"
          resource.attributes = resource_attributes(resource, action)
          resource = resource
        else
          resource = nil
        end
      elsif action == 'index'
        resource = policy_scope(scope) # Treat as collection for index
      elsif resource_id
        resource = scope.find_by(find_by_attribute => resource_id) # Use the custom find_by attribute
      else
        resource = policy_scope(scope) # Treat as collection for non-standard actions
      end

      resource
    end

    def load_parent_resources(parents)
      Array(parents).each do |parent|
        parent_resource_name = parent.to_s.singularize
        parent_id = params["#{parent_resource_name}_id"]
        parent_instance = instance_variable_get("@#{parent_resource_name}")

        unless parent_instance
          parent_scope = parent_resource_name.classify.constantize
          parent_instance = parent_scope.find(parent_id)
          instance_variable_set("@#{parent_resource_name}", parent_instance)
          authorize parent_instance, :show?
        end

        parent_instance
      end
    end

    def authorize_resource(resource_name = nil, options = {})
      resource_name = (resource_name || controller_name.singularize).to_s
      instance_name = (options[:instance_name] || resource_name).to_s
      resource = instance_variable_get("@#{instance_name}") || resource_name.classify.constantize

      # Determine if this is a parent resource by checking if it was listed as a `through` resource
      is_parent_resource = self.class.resource_options.any? do |opt|
        opt[:options][:through] && Array(opt[:options][:through]).include?(resource_name.to_sym)
      end

      action = is_parent_resource ? :show : params[:action].to_sym
      if resource_name != controller_name.singularize
        action = :show
      end

      if resource.is_a?(Class)
        authorize resource, "#{params[:action].to_sym}?"
      else
        authorize resource, "#{action}?"
      end
    end

    def skip_authorization_and_scope
      action = params[:action]
      skip_policy_scope if action == 'index'
      skip_authorization
    end

    def resource_name
      controller_name.singularize
    end

    def resource_class
      resource_name.classify.constantize
    end

    def resource_instance
      instance_variable_get "@#{resource_name}"
    end

    def resource_attributes(resource, action)
      attributes = {}

      # Get permitted attributes if they are defined
      if has_permitted_attributes?(resource, action)
        attributes = permitted_attributes(resource)
      else
        candidates = ["#{action}_params", "#{resource_name}_params"]
        candidates.each do |candidate|
          if respond_to?(candidate, true)
            attributes.merge!(send(candidate)) { |key, old_val, new_val| old_val }
            break
          end
        end
      end

      # Extract URL parameters that are part of the resource's attributes
      url_param_keys = request.path_parameters.keys.map(&:to_sym)

      # Remove :id from the keys to ensure it isn't included
      url_param_keys.delete(:id)

      relevant_url_params = params.slice(*url_param_keys).permit!.to_h

      # Merge only the relevant URL parameters that match resource's column names
      relevant_url_params.each do |key, value|
        if resource.class.column_names.include?(key.to_s)
          attributes[key.to_sym] ||= value
        end
      end

      attributes
    end

    def has_permitted_attributes?(resource, action)
      return true if policy(resource).respond_to? :"permitted_attributes_for_#{action}"
      return true if policy(resource).respond_to? :permitted_attributes

      false
    end
  end
end