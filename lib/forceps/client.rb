module Forceps
  class Client
    attr_reader :options
    cattr_accessor :options_class

    def configure(options={})
      @options = options.merge(default_options)
      Forceps::Client.options_class=@options
      @model_classes=nil
      @remote_classes_defined =  nil

      declare_remote_model_classes
      make_associations_reference_remote_classes

      logger.debug "Classes handled by Forceps: #{model_classes.collect(&:name).inspect}"
    end

    def master_domain
      @options[:master]
    end

    def self.master_domain
      options_class[:master]
    end

    def master_code
      S3i_Domain.domain(master_domain).code
    end
    
    def self.master_code
      S3i_Domain.domain(master_domain).code
    end
    
    private

    def connection_to_master
      p "****** connecting #{self} to Master #{master_domain}"
      domain=S3i_Domain.domain(master_domain)

      db_user=S3i_entity.db_user_root
      db_password=S3i_Domain.user_password(domain, db_user)
      new_connection=domain.connectionstr.merge({
          "username" => db_user, 
          "password" => db_password,
          :username => db_user, 
          :password => db_password})

      new_connection
    end

    def logger
      Forceps.logger
    end

    def default_options
      {}
    end

    def model_classes
      @model_classes ||= filtered_model_classes
    end

    def filtered_model_classes
      @options[:models].collect{|x| x.camelize.constantize}
    end

    def model_classes_to_exclude
      if Rails::VERSION::MAJOR >= 4
        [ActiveRecord::SchemaMigration, ]
      else
        []
      end
    end

    def declare_remote_model_classes
      return if @remote_classes_defined
      model_classes.each { |remote_class| declare_remote_model_class(remote_class) }
      @remote_classes_defined = true
    end

    def declare_remote_model_class(klass)
      full_class_name = klass.name
      head = Forceps::Remote

      path = full_class_name.split("::")
      class_name = path.pop

      path.each do |module_name|
        if head.const_defined?(module_name, false)
          head = head.const_get(module_name, false)
        else
          head = head.const_set(module_name, Module.new)
        end
      end
      head.const_set(class_name, build_new_remote_class(klass))

      #p "Remote connection to #{connection_to_master}"
      remote_class_for(full_class_name).establish_connection connection_to_master #:remote
    end

    def build_new_remote_class(local_class)
      needs_type_condition = (local_class.base_class != ActiveRecord::Base) && local_class.finder_needs_type_condition?
      Class.new(local_class) do
        self.table_name = local_class.table_name

        include Forceps::ActsAsCopyableModel
#        include Sinai::S3iRemoteModels
        default_scope lambda { where(:entitycode => self.master_code) }

        # def self.master_domain
        #   S3i_Domain.domain(master_domain).code #{}"am000"
        # end

        def self.master_code
          Forceps::Client.master_code
        end
        
        # Intercept instantiation of records to make the 'type' column point to the corresponding remote class
        if Rails::VERSION::MAJOR >= 4
          def self.instantiate(record, column_types = {})
            __make_sti_column_point_to_forceps_remote_class(record)
            super
          end
        else
          def self.instantiate(record)
            __make_sti_column_point_to_forceps_remote_class(record)
            super
          end
        end

        def self.__make_sti_column_point_to_forceps_remote_class(record)
          if record[inheritance_column].present?
            record[inheritance_column] = "Forceps::Remote::#{record[inheritance_column]}"
          end
        end

        # We don't want to include STI condition automatically (the base class extends the original one)
        unless needs_type_condition
          def self.finder_needs_type_condition?
            false
          end
        end
      end
    end

    def remote_class_for(full_class_name)
      head = Forceps::Remote
      full_class_name.split("::").each do |mod|
        head = head.const_get(mod)
      end
      head
    end

    def make_associations_reference_remote_classes
      model_classes.each do |model_class|
        make_associations_reference_remote_classes_for(model_class)
      end
    end

    def make_associations_reference_remote_classes_for(model_class)
      model_class.reflect_on_all_associations.each do |association|
        next if association.class_name =~ /Forceps::Remote/ rescue next
        reference_remote_class(model_class, association)
      end
    end

    def reference_remote_class(model_class, association)
      remote_model_class = remote_class_for(model_class.name)

      if association.options[:polymorphic]
        reference_remote_class_in_polymorphic_association(association, remote_model_class)
      else
        reference_remote_class_in_normal_association(association, remote_model_class)
      end
    end

    def reference_remote_class_in_polymorphic_association(association, remote_model_class)
      foreign_type_attribute_name = association.foreign_type

      remote_model_class.send(:define_method, association.foreign_type) do
        "Forceps::Remote::#{super()}"
      end

      remote_model_class.send(:define_method, "[]") do |attribute_name|
        if (attribute_name.to_s == foreign_type_attribute_name)
          "Forceps::Remote::#{super(attribute_name)}"
        else
          super(attribute_name)
        end
      end
    end

    def reference_remote_class_in_normal_association(association, remote_model_class)
      related_remote_class = remote_class_for(association.klass.name)

      cloned_association = association.dup
      cloned_association.instance_variable_set("@klass", related_remote_class)

      ActiveRecord::Reflection.add_reflection(remote_model_class, cloned_association.name, cloned_association)
    end
  end
end
