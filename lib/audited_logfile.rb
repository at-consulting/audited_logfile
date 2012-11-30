require 'audited'
require 'audited/adapters/active_record'

module AuditedLogfile
  mattr_accessor :logfile
  @@loger = nil

  def self.setup
    yield self
  end

  def self.logfile
    @@logfile || 'log/audit.log'
  end

  def self.logger
    unless @@loger
      @@loger = Logger.new(logfile)
      @@loger.level = Logger::INFO
    end
    @@loger
  end
end

module Audited
  module Adapters
    module ActiveRecord
      class Audit < ::ActiveRecord::Base
        DO_NOT_LOG = true
        after_create do |record|
          changes = audited_changes.map { |k, v| "#{k}: [#{v.first}, #{v.last}]"}.join(', ')
          AuditedLogfile.logger.info "#{Time.now.iso8601(1)}, #{action.upcase}, #{user.try(:email) || 'Guest'}, #{auditable_type}, #{auditable_id}, (#{changes})"
        end
      end
    end
  end
end

module ActiveRecord
  class Base
    class << self
      alias_method :inherited_orig, :inherited

      def inherited(subclass)
        unless defined? subclass::DO_NOT_LOG
          subclass.class_eval %(
            audited :allow_mass_assignment => true
            attr_protected :audit_ids
          )
        end
        inherited_orig(subclass)
      end
    end
  end
end

Warden::Manager.after_authentication do |user,auth,opts|
  AuditedLogfile.logger.info "#{Time.now.iso8601(1)}, SIGNIN, #{user.email}"
end

Warden::Manager.before_logout do |user,auth,scope|
  AuditedLogfile.logger.info "#{Time.now.iso8601(1)}, SIGNOUT, #{user && user.email}"
end