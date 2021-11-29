require 'rubygems'
require 'active_support'
require 'active_support/duration'
require 'date_time_attribute/container'
require 'date_time_attribute/railtie' if defined?(Rails)

module DateTimeAttribute
  VERSION = '0.1.2'

  extend ActiveSupport::Concern

  def self.parser
    DateTimeAttribute::Container.parser
  end

  # @param val Any adapter responding to #parse
  def self.parser=(val)
    DateTimeAttribute::Container.parser = val
  end

  # @param [Symbol] attribute
  # @return [Container]
  def date_time_container(attribute)
    (@date_time_container ||= {})[attribute] ||= DateTimeAttribute::Container.new(send(attribute))
  end

  # @param [String, Symbol, Proc, nil] zone Time zone
  def in_time_zone(zone)
    case zone
    when nil
      yield
    when ActiveSupport::TimeZone, String
      old_zone = Time.zone
      Time.zone = zone
      yield(zone).tap { Time.zone = old_zone }
    when Proc, Symbol
      old_zone = Time.zone
      zone = instance_eval(&(zone.to_proc))
      Time.zone = zone
      yield(zone).tap { Time.zone = old_zone }
    else
      raise ArgumentError, "Expected timezone, got #{zone.inspect}"
    end
  end

  module ClassMethods

    # @param [Symbol] attribute Attribute name
    # @param [Hash<Symbol>] opts
    # @option opts [String, Symbol, Proc, nil] :time_zone
    def date_time_attribute(*attributes)
      opts = attributes.extract_options!
      time_zone = opts[:time_zone]

      attributes.each do |attribute|
        attribute = attribute.to_sym
        is_active_record_attribute = respond_to?(:attribute_method?) && attribute_method?(attribute)

        # ActiveRecord lazy initialization issue: https://github.com/einzige/date_time_attribute/issues/2
        if is_active_record_attribute && !@attribute_methods_generated
          define_attribute_methods
        end

        attr_accessor attribute unless method_defined?(attribute)

        define_method("#{attribute}_date") do
          in_time_zone(time_zone) do |time_zone|
            date_time_container(attribute).in_time_zone(time_zone).date
          end
        end

        alias_method "old_#{attribute}=", "#{attribute}="

        define_method("#{attribute}=") do |val|
          in_time_zone(time_zone) do |time_zone|
            container = date_time_container(attribute).in_time_zone(time_zone)
            container.date_time = val
            self.send("old_#{attribute}=", container.date_time)
          end
        end

        define_method("#{attribute}_time") do
          in_time_zone(time_zone) do |time_zone|
            date_time_container(attribute).in_time_zone(time_zone).time
          end
        end

        define_method("#{attribute}_time_zone") do
          in_time_zone(time_zone) do |time_zone|
            date_time_container(attribute).in_time_zone(time_zone).time_zone
          end
        end

        define_method("#{attribute}_date=") do |val|
          in_time_zone(time_zone) do |time_zone|
            container = date_time_container(attribute).in_time_zone(time_zone)
            (container.date = val).tap do
              self.send("#{attribute}=", container.date_time)
            end
          end
        end

        define_method("#{attribute}_time=") do |val|
          in_time_zone(time_zone) do |time_zone|
            container = date_time_container(attribute).in_time_zone(time_zone)
            (container.time = val).tap do
              self.send("#{attribute}=", container.date_time)
            end
          end
        end

        define_method("#{attribute}_time_zone=") do |val|
          in_time_zone(val) do |time_zone|
            container = date_time_container(attribute).in_time_zone(time_zone)
            self.send("#{attribute}=", container.date_time)
            container.time_zone
          end if val
        end
      end

      attributes.each do |attribute|
        validate -> { self.send("#{attribute}_datetime_value_valid") }

        # allow resetting the field to nil
        before_validation do
          if self.instance_variable_get("@#{attribute}_is_set")
            date = self.instance_variable_get("@#{attribute}_date_value")
            time = self.instance_variable_get("@#{attribute}_time_value")
            if date.blank? && time.blank?
              self.send("#{attribute}=", nil)
            end
          end
        end

        # remember old date and time values
        define_method("#{attribute}_date_value=") do |val|
          self.instance_variable_set("@#{attribute}_is_set", true)
          self.instance_variable_set("@#{attribute}_date_value", val)
          self.send("#{attribute}_date=", val) rescue nil
        end
        define_method("#{attribute}_time_value=") do |val|
          self.instance_variable_set("@#{attribute}_is_set", true)
          self.instance_variable_set("@#{attribute}_time_value", val)
          self.send("#{attribute}_time=", val) rescue nil
        end

        # fallback to field when values are not set
        define_method("#{attribute}_date_value") do
          self.instance_variable_get("@#{attribute}_date_value") || self.send("#{attribute}_date").try { |e| e.strftime('%Y-%m-%d') }
        end
        define_method("#{attribute}_time_value") do
          self.instance_variable_get("@#{attribute}_time_value") || self.send("#{attribute}_time").try { |e| e.strftime('%H:%M') }
        end

        private

        # validate date and time
        define_method("#{attribute}_datetime_value_valid") do
          date = self.instance_variable_get("@#{attribute}_date_value")
          unless date.blank? || (Date.parse(date) rescue nil)
            errors.add(attribute, "is not a valid date") # @todo I18n
          end
          time = self.instance_variable_get("@#{attribute}_time_value")
          unless time.blank? || (Time.parse(time) rescue nil)
            errors.add(attribute, "is not a valid time") # @todo I18n
          end
        end
      end
    end
  end
end
