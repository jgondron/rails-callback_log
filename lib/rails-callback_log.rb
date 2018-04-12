require "rails_callback_log/version"

# Make sure `ActiveSupport::Callbacks` is loaded before we continue.
require "active_support/all"

module RailsCallbackLog
  # Filtering is very expensive. It makes my test suite more than 50%
  # slower. So, it's off by default.
  FILTER = ENV["RAILS_CALLBACK_LOG_FILTER"].present?.freeze
  FORMAT = (ENV["RAILS_CALLBACK_LOG_FORMAT"] || "Callback %s").freeze

  class << self
    def logger
      ::Rails.logger || ::Logger.new(STDOUT)
    end

    def matches_filter?(str)
      source_location_filters.any? { |f| str.start_with?(f) }
    end

    private

    def source_location_filters
      @@filters ||= %w(app lib).map { |dir| (::Rails.root + dir).to_s }
    end
  end

  # In rails 5.1, we extend `CallTemplate`.
  module CallTemplateExtension
    # Returns a lambda that wraps `super`, adding logging.
    def make_lambda
      original_lambda = super
      lambda { |*args, &block|
        if !::RailsCallbackLog::FILTER ||
          caller.any? { |line| ::RailsCallbackLog.matches_filter?(line) }
          target, block, method, *arguments = expand(*args, block)
          source_file, source_line = target.method(method).source_location
          ::RailsCallbackLog.logger.debug(format(::RailsCallbackLog::FORMAT, method, source_file, source_line))
        end
        original_lambda.call(*args, &block)
      }
    end
  end

  # In rails 4.2 and 5.0, we extend `Callback`.
  module CallbackExtension
    # Returns a lambda that wraps `super`, adding logging.
    def make_lambda(filter)
      original_lambda = super(filter)
      lambda { |*args, &block|
        if !::RailsCallbackLog::FILTER ||
          caller.any? { |line| ::RailsCallbackLog.matches_filter?(line) }
          target, block, method, *arguments = expand(*args, block)
          source_file, source_line = target.method(method).source_location
          ::RailsCallbackLog.logger.debug(format(::RailsCallbackLog::FORMAT, method, source_file, source_line))
        end
        original_lambda.call(*args, &block)
      }
    end
  end
end

# Install our `CallbackExtension` using module prepend.
module ActiveSupport
  module Callbacks
    if ::ActiveSupport.gem_version >= ::Gem::Version.new("5.1.0")
      class CallTemplate
        prepend ::RailsCallbackLog::CallTemplateExtension
      end
    else
      class Callback
        prepend ::RailsCallbackLog::CallbackExtension
      end
    end
  end
end
