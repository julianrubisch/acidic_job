# frozen_string_literal: true

require "active_support/concern"

module AcidicJob
  module PerformTransactionallyExtension
    extend ActiveSupport::Concern

    class_methods do
      def perform_transactionally(*args)
        attributes = if defined?(ActiveJob) && self < ActiveJob::Base
          {
            adapter: "activejob",
            job_name: name,
            job_args: job_or_instantiate(*args).serialize
          }
        elsif defined?(Sidekiq) && include?(Sidekiq::Worker)
          {
            adapter: "sidekiq",
            job_name: name,
            job_args: args
          }
        else
          raise UnknownJobAdapter
        end

        AcidicJob::Staged.create!(attributes)
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
