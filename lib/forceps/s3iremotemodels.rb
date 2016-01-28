require 'active_support/concern'

module Sinai
    module S3iRemoteModels
      extend ActiveSupport::Concern
       
      included do
        default_scope lambda { where(:entitycode => master_domain_entitycode) }
        cattr_accessor :current_domain
      end
       
      module ClassMethods
        def master_domain_entitycode
          p "master_domain_entitycode"
          current_domain=S3i_Domain.domain(master_domain) unless current_domain
          current_domain.code
        end
  
        def master_domain
          "master.amiritmokids.es"
        end
  
        def connection_to_master
          p "****** connecting #{self} to Master #{master_domain}"
          domain=S3i_Domain.domain(master_domain)
          Sinai.log "Trying connect to #{master_domain}/#{S3i_entity.db_user_root}"

          #Remote::Counter.current_domain=domain

          db_user=S3i_entity.db_user_root
          db_password=S3i_Domain.user_password(domain, db_user)
          new_connection=domain.connectionstr.merge({
              "username" => db_user, 
              "password" => db_password,
              :username => db_user, 
              :password => db_password})

          new_connection
          # Sinai.log "Trying connect from #{master_domain} to #{new_connection}"
          # begin
          #   ActiveRecord::Base.establish_connection new_connection
          #   ActiveRecord::Base.connection.execute "select count(*) from dual;"
          #   Sinai.log "Connect succesfully from #{master_domain} to #{new_connection}"
          # rescue
          #   raise Sinai::S3iCanNotConnectException.new("cannot connect to database with #{new_connection} with user #{db_user}")
          # end
        end
      end

    end
end

puts "Loaded Sinai::S3iRemoteModels"


