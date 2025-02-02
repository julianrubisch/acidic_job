# frozen_string_literal: true

require "test_helper"

class MyJob
  def self.deserialize(_serialized_job)
    new
  end

  def enqueue; end
end

class TestAcidicJobRun < ActiveSupport::TestCase
  def before_setup
    super()
    AcidicJob::Run.delete_all
    Performance.reset!
  end

  def test_that_it_validates_serialized_job_present
    run = AcidicJob::Run.new
    run.valid?

    assert_includes run.errors.messages, :serialized_job
    assert_equal run.errors.messages[:serialized_job], ["can't be blank"]
  end

  def test_that_it_validates_idempotency_key_present
    run = AcidicJob::Run.new
    run.valid?

    assert_includes run.errors.messages, :idempotency_key
    assert_equal run.errors.messages[:idempotency_key], ["can't be blank"]
  end

  def test_that_it_validates_job_class_present
    run = AcidicJob::Run.new
    run.valid?

    assert_includes run.errors.messages, :job_class
    assert_equal run.errors.messages[:job_class], ["can't be blank"]
  end

  def test_that_it_validates_last_run_at_present_if_not_staged
    unstaged_run = AcidicJob::Run.new(staged: false)
    unstaged_run.valid?

    assert_includes unstaged_run.errors.messages, :last_run_at
    assert_equal unstaged_run.errors.messages[:last_run_at], ["can't be blank"]

    staged_run = AcidicJob::Run.new(staged: true)
    staged_run.valid?

    assert_empty staged_run.errors.messages[:last_run_at]
  end

  def test_that_it_validates_recovery_point_present_if_not_staged
    unstaged_run = AcidicJob::Run.new(staged: false)
    unstaged_run.valid?

    assert_includes unstaged_run.errors.messages, :recovery_point
    assert_equal unstaged_run.errors.messages[:recovery_point], ["can't be blank"]

    staged_run = AcidicJob::Run.new(staged: true)
    staged_run.valid?

    assert_empty staged_run.errors.messages[:recovery_point]
  end

  def test_that_it_validates_workflow_present_if_not_staged
    unstaged_run = AcidicJob::Run.new(staged: false)
    unstaged_run.valid?

    assert_includes unstaged_run.errors.messages, :workflow
    assert_equal unstaged_run.errors.messages[:workflow], ["can't be blank"]

    staged_run = AcidicJob::Run.new(staged: true)
    staged_run.valid?

    assert_empty staged_run.errors.messages[:workflow]
  end

  def test_enqueue_staged_job_only_runs_for_staged_jobs
    job_mock = MiniTest::Mock.new
    job_mock.expect :enqueue, true

    MyJob.stub :deserialize, job_mock do
      AcidicJob::Run.create!(staged: true, job_class: MyJob, idempotency_key: 1,
                             serialized_job: { "job_class" => "MyJob", "job_id" => nil })
    end

    job_mock.verify

    # create an unstaged run that would blow up if it was enqueued
    unstaged_job = AcidicJob::Run.create!(staged: false, job_class: MyJob, idempotency_key: 2,
                                          serialized_job: { "job_class" => "MyJob", "job_id" => nil },
                                          last_run_at: Time.now, recovery_point: "a", workflow: { a: "a" })

    # test calling `enqueue_job` directly still won't run for an unstaged job
    unstaged_job.send(:enqueue_job)
  end

  def test_purging_finished_runs_without_relation
    default_attributes = {
      staged: false,
      job_class: MyJob,
      serialized_job: { "job_class" => "MyJob", "job_id" => nil },
      last_run_at: Time.now,
      recovery_point: "a",
      workflow: { a: "a" }
    }
    finished = AcidicJob::Run::FINISHED_RECOVERY_POINT

    AcidicJob::Run.create!(default_attributes.merge(recovery_point: :started, error_object: nil,
                                                    idempotency_key: rand))
    AcidicJob::Run.create!(default_attributes.merge(recovery_point: :started, error_object: "T",
                                                    idempotency_key: rand))
    AcidicJob::Run.create!(default_attributes.merge(recovery_point: finished, error_object: nil,
                                                    idempotency_key: rand))
    AcidicJob::Run.create!(default_attributes.merge(recovery_point: finished, error_object: "T",
                                                    idempotency_key: rand))

    assert_equal 4, AcidicJob::Run.count
    assert_equal 2, AcidicJob::Run.clear_finished
  end

  def test_purging_finished_runs_with_relation
    default_attributes = {
      staged: false,
      job_class: MyJob,
      serialized_job: { "job_class" => "MyJob", "job_id" => nil },
      last_run_at: Time.now,
      recovery_point: "a",
      workflow: { a: "a" }
    }
    finished = AcidicJob::Run::FINISHED_RECOVERY_POINT

    AcidicJob::Run.create!(default_attributes.merge(recovery_point: :started, error_object: nil,
                                                    idempotency_key: rand))
    AcidicJob::Run.create!(default_attributes.merge(recovery_point: :started, error_object: "T",
                                                    idempotency_key: rand))
    AcidicJob::Run.create!(default_attributes.merge(recovery_point: finished, error_object: nil,
                                                    idempotency_key: rand))
    AcidicJob::Run.create!(default_attributes.merge(recovery_point: finished, error_object: "T",
                                                    idempotency_key: rand))

    assert_equal 4, AcidicJob::Run.count
    assert_equal 0, AcidicJob::Run.where(recovery_point: :started).clear_finished
  end
end
