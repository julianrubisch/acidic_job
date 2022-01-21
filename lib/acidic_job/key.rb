# frozen_string_literal: true

require "active_record"

module AcidicJob
  class Key < ActiveRecord::Base
    RECOVERY_POINT_FINISHED = "FINISHED"

    self.table_name = "acidic_job_keys"

    serialize :error_object
    serialize :job_args
    serialize :workflow
    store :attr_accessors

    validates :idempotency_key, presence: true, uniqueness: {scope: %i[job_name job_args]}
    validates :job_name, presence: true
    validates :last_run_at, presence: true
    validates :recovery_point, presence: true

    def finished?
      recovery_point == RECOVERY_POINT_FINISHED
    end

    def succeeded?
      finished? && !failed?
    end

    def failed?
      error_object.present?
    end
  end
end
