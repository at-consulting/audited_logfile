require 'audited'
require 'audited/adapters/active_record'

module AuditedLogfile
  mattr_accessor :logfile
  mattr_accessor :skip
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

  def self.skip
    @@skip || []
  end
end

module Audited
  module Adapters
    module ActiveRecord
      class Audit < ::ActiveRecord::Base
        before_create do |record|
          changes = audited_changes.map { |k, v| "#{k}: #{v.is_a?(Array) ? "[#{v.first}, #{v.last}]" : v}"}.join(', ')
          user_info = user ? "#{user_type}(#{user_id}): #{user.try(:email)}" : 'Guest'
          AuditedLogfile.logger.info "#{Time.now.iso8601(1)}, #{action.upcase}, #{user_info}, #{auditable_type}, #{auditable_id}, (#{changes})"
        end
      end
    end
  end

  class Sweeper < ActiveModel::Observer
    def current_user
      if Audited.current_user_method.is_a? Array
        Audited.current_user_method.map do |method|
          controller.send(method) if controller.respond_to?(method, true)
        end.compact.first
      else
        controller.send(Audited.current_user_method) if controller.respond_to?(Audited.current_user_method, true)
      end
    end
  end
end

module ActiveRecord
  class Base
    class << self
      alias_method :inherited_orig, :inherited

      def inherited(subclass)
        unless subclass.name.in? AuditedLogfile.skip
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
  AuditedLogfile.logger.info "#{Time.now.iso8601(1)}, SIGNIN, #{user.class}(#{user.id}): #{user.email}"
end

Warden::Manager.before_logout do |user,auth,scope|
  AuditedLogfile.logger.info "#{Time.now.iso8601(1)}, SIGNOUT, #{user.class}(#{user.id}): #{user.email}"
end
