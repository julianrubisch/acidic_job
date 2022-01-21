# frozen_string_literal: true

require "sidekiq/testing"

unless defined? Sidekiq::Batch
  module Sidekiq
    class Batch
      class Status; end
    end
  end
end

module Support
  module Sidekiq
    class NullObject
      def method_missing(*_args)
        self
      end

      def respond_to_missing?(*_args)
        true
      end
    end

    class NullBatch < NullObject
      attr_accessor :description
      attr_reader :bid

      def initialize(bid = nil)
        super()
        @bid = bid || SecureRandom.hex(8)
        @callbacks = []
      end

      def status
        NullStatus.new(@bid, @callbacks)
      end

      def on(*args)
        @callbacks << args
      end

      def jobs(*)
        yield
      end
    end

    class NullStatus < NullObject
      attr_reader :bid

      def initialize(bid = SecureRandom.hex(8), callbacks = [])
        super()
        @bid = bid
        @callbacks = callbacks
      end

      def failures
        0
      end

      def join
        ::Sidekiq::Worker.drain_all

        @callbacks.each do |event, callback, options|
          next unless event != :success || failures.zero?

          case callback
          when Class
            callback.new.send("on_#{event}", self, options)
          when String
            klass, meth = callback.split("#")
            klass.constantize.new.send(meth, self, options)
          else
            raise ArgumentError, "Unsupported callback notation"
          end
        end
      end
      # rubocop:enable Metrics/MethodLength

      def total
        ::Sidekiq::Worker.jobs.size
      end
    end

    class Workflow
      def batch
        ObjectSpace.each_object(Support::Sidekiq::NullBatch).find do |null_batch|
          success_callback = null_batch.instance_variable_get(:@callbacks).find { |on, *| on == :success }
          success_callback&.second == self.class
        end
      end
    end

    class StepWorker
      include ::Sidekiq::Worker

      def call_batch_success_callback
        # simulate the Sidekiq::Batch success callback
        success_callback = batch.instance_variable_get(:@callbacks).find { |on, *| on == :success }
        _, method_sig, options = success_callback
        class_name, method_name = method_sig.split("#")
        class_name.constantize.new.send(method_name, batch.status, options)
      end

      def batch
        ObjectSpace.each_object(Support::Sidekiq::NullBatch).find do |null_batch|
          success_callback = null_batch.instance_variable_get(:@callbacks).find { |on, *| on == :success }
          _event, receiver = success_callback

          receiver.is_a?(String) && receiver.end_with?("#step_done")
        end
      end
    end
  end
end
