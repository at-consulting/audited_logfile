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

  module ActiveRecord
    class LogSubscriber < ActiveSupport::LogSubscriber
      def sql(event)
        if event.payload[:sql] =~ /\ASELECT/i
          user = Thread.current[:sql_audit_user]
          user_info = user ? "#{user.class}(#{user.id}): #{user.try(:email)}" : 'Unknown'
          AuditedLogfile.logger.info "#{Time.now.iso8601(1)}, SELECT, #{user_info}, `#{event.payload[:sql]}`"
        end
      end

      attach_to :active_record
    end
  end
end

module Audited
  module Adapters
    module ActiveRecord
      class Audit < ::ActiveRecord::Base
        before_create do |record|
          if changes.is_a? Hash
            changes = audited_changes.map { |k, v| "#{k}: #{v.is_a?(Array) ? "[#{v.first.inspect}, #{v.last.inspect}]" : v}"}.join(', ')
          end

          user_info = user ? "#{user_type}(#{user_id}): #{user.try(:email)}" : 'Unknown'
          common_log = "#{Time.now.iso8601(1)}, #{action.upcase}, #{user_info}"

          case action.to_s
          when 'create', 'update', 'destroy'
            AuditedLogfile.logger.info "#{common_log}, #{auditable_type}, #{auditable_id}, (#{changes})"
          else
            AuditedLogfile.logger.info "#{common_log}, #{audited_changes.inspect}"
          end
        end
      end
    end
  end

  class Sweeper < ActiveModel::Observer
    def before(controller)
      self.controller = controller
      Thread.current[:sql_audit_user] = current_user
      true
    end

    def after(controller)
      self.controller = nil
      Thread.current[:sql_audit_user] = nil
    end

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

  def self.report(options)
    action = options[:action] || 'report'
    Adapters::ActiveRecord::Audit.create!(action: action, audited_changes: options)
  end

  def self.week_activity_chart_data(actions)
    records = Adapters::ActiveRecord::Audit
      .select("TO_CHAR(created_at, 'DD') DAY, TO_CHAR(created_at, 'MM') MONTH, TO_CHAR(created_at, 'YYYY') YEAR")
      .where(action: actions)
      .where('created_at >= ? AND created_at < ?', Date.today - 6, Date.today + 1)
    data = Hash[Adapters::ActiveRecord::Audit
      .find_by_sql("SELECT DAY, MONTH, YEAR, COUNT(*) COUNT FROM (#{records.to_sql}) GROUP BY YEAR, MONTH, DAY ORDER BY YEAR, MONTH, DAY")
      .map { |x| [Date.new(x.year.to_i, x.month.to_i, x.day.to_i), x.count.to_i] }]
    (Date.today - 6 .. Date.today).map { |day| [day, (data[day] || 0)] }
  end
end

module ActiveRecord
  class Base
    class << self
      alias_method :inherited_orig, :inherited

      def inherited(subclass)
        unless AuditedLogfile.skip.include? subclass.name
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
  if user.present?
    user_info = "#{user.class}(#{user.id}): #{user.email}"
    AuditedLogfile.logger.info "#{Time.now.iso8601(1)}, SIGNIN, #{user_info}"
  end
end

Warden::Manager.before_logout do |user,auth,scope|
  if user.present?
    user_info = "#{user.class}(#{user.id}): #{user.email}"
    AuditedLogfile.logger.info "#{Time.now.iso8601(1)}, SIGNOUT, #{user_info}"
  end
end
