# frozen_string_literal: true

require "active_job/serializers"
require "active_job/arguments"
require "json"

class WorkerSerializer < ActiveJob::Serializers::ObjectSerializer
  def serialize(worker)
    # {"_aj_serialized"=>"WorkerSerializer", "class"=>"SuccessfulArgWorker", "args"=>[123], "kwargs"=>{}}]
    super(
      "class" => worker.class,
      "args" => worker.instance_variable_get(:@__acidic_job_args),
      "kwargs" => worker.instance_variable_get(:@__acidic_job_kwargs)
    )
  end

  def deserialize(hash)
    worker_class = hash["class"].constantize
    worker_class.new(*hash["args"], **hash["kwargs"])
  end

  def serialize?(argument)
    defined?(Sidekiq) && argument.class.include?(Sidekiq::Worker)
  end
end

class ExceptionSerializer < ActiveJob::Serializers::ObjectSerializer
  def serialize(exception)
    hash = {
      "class" => exception.class,
      "message" => exception.message,
      "cause" => exception.cause,
      "backtrace" => {}
    }

    exception.backtrace.map do |trace|
      path, _, location = trace.rpartition("/")

      next if hash["backtrace"].key?(path)

      hash["backtrace"][path] = location
    end

    super(hash)
  end

  def deserialize(hash)
    exception_class = hash["class"].constantize
    exception = exception_class.new(hash["message"])
    exception.set_backtrace hash["backtrace"].map do |path, location|
      [path, location].join("/")
    end
    exception
  end

  def serialize?(argument)
    defined?(Exception) && argument.is_a?(Exception)
  end
end

class FinishedPointSerializer < ActiveJob::Serializers::ObjectSerializer
  def serialize(finished_point)
    super(
      "class" => finished_point.class
    )
  end

  def deserialize(hash)
    finished_point_class = hash["class"].constantize
    finished_point_class.new
  end

  def serialize?(argument)
    defined?(::AcidicJob::FinishedPoint) && argument.is_a?(::AcidicJob::FinishedPoint)
  end
end

class RecoveryPointSerializer < ActiveJob::Serializers::ObjectSerializer
  def serialize(recovery_point)
    super(
      "class" => recovery_point.class,
      "name" => recovery_point.name
    )
  end

  def deserialize(hash)
    recovery_point_class = hash["class"].constantize
    recovery_point_class.new(hash["name"])
  end

  def serialize?(argument)
    defined?(::AcidicJob::RecoveryPoint) && argument.is_a?(::AcidicJob::RecoveryPoint)
  end
end

ActiveJob::Serializers.add_serializers WorkerSerializer, ExceptionSerializer, FinishedPointSerializer,
                                       RecoveryPointSerializer

# ...
module AcidicJob
  module Arguments
    include ActiveJob::Arguments

    module_function

    # `ActiveJob` will throw an error if it tries to deserialize a GlobalID record.
    # However, this isn't the behavior that we want for our custom `ActiveRecord` serializer.
    # Since `ActiveRecord` does _not_ reset instance record state to its pre-transactional state
    # on a transaction ROLLBACK, we can have GlobalID entries in a serialized column that point to
    # non-persisted records. This is ok. We should simply return `nil` for that portion of the
    # serialized field.
    def deserialize_global_id(hash)
      GlobalID::Locator.locate hash[GLOBALID_KEY]
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end

  class Serializer
    # Used for `serialize` method in ActiveRecord
    class << self
      def load(json)
        return if json.nil? || json.empty?

        data = JSON.parse(json)
        Arguments.deserialize(data).first
      end

      def dump(obj)
        data = Arguments.serialize [obj]
        data.to_json
      end
    end
  end
end
