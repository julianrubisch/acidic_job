# frozen_string_literal: true

require "test_helper"
require "sidekiq"
require "sidekiq/testing"
require_relative "support/setup"

class CustomErrorForTesting < StandardError; end

class WorkerWithRescueInPerform
  include Sidekiq::Worker
  include AcidicJob

  def perform
    with_acidity given: {} do
      step :do_something
    end
  rescue CustomErrorForTesting
    true
  end

  def do_something
    raise CustomErrorForTesting
  end
end

class WorkerWithErrorInsidePhaseTransaction
  include Sidekiq::Worker
  include AcidicJob

  def perform
    with_acidity given: {accessor: nil} do
      step :do_something
    end
  end

  def do_something
    self.accessor = "value"
    raise CustomErrorForTesting
  end
end

class WorkerWithLogicInsideAcidicBlock
  include Sidekiq::Worker
  include AcidicJob

  def perform(bool)
    with_acidity given: {} do
      step :do_something if bool
    end
  end

  def do_something
    raise CustomErrorForTesting
  end
end

class WorkerWithOldSyntax
  include Sidekiq::Worker
  include AcidicJob

  def perform
    idempotently with: {} do
      step :do_something
    end
  end

  def do_something
    raise CustomErrorForTesting
  end
end

class WorkerWithoutStepsInsideAcidicBlock
  include Sidekiq::Worker
  include AcidicJob

  def perform(bool)
    with_acidity given: {} do
      bool
    end
  end
end

class TestEdgeCases < Minitest::Test
  def before_setup
    super
    DatabaseCleaner.start
    Sidekiq::Queues.clear_all
  end

  def after_teardown
    Sidekiq::Queues.clear_all
    DatabaseCleaner.clean
    super
  end

  def test_rescued_error_in_perform_does_not_prevent_error_object_from_being_stored
    WorkerWithRescueInPerform.new.perform

    assert_equal 1, AcidicJob::Key.count
    assert_equal CustomErrorForTesting, AcidicJob::Key.first.error_object.class
  end

  def test_error_in_first_step_rolls_back_step_transaction
    assert_raises CustomErrorForTesting do
      WorkerWithErrorInsidePhaseTransaction.new.perform
    end

    assert_equal 1, AcidicJob::Key.count
    assert_equal CustomErrorForTesting, AcidicJob::Key.first.error_object.class
    assert_equal AcidicJob::Key.first.attr_accessors, {"accessor" => nil}
  end

  def test_logic_inside_acidic_block_is_executed_appropriately
    assert_raises CustomErrorForTesting do
      WorkerWithLogicInsideAcidicBlock.new.perform(true)
    end

    assert_raises AcidicJob::NoDefinedSteps do
      WorkerWithLogicInsideAcidicBlock.new.perform(false)
    end

    assert_equal 1, AcidicJob::Key.count
  end

  def test_deprecated_syntax_is_executed_appropriately
    assert_raises CustomErrorForTesting do
      WorkerWithOldSyntax.new.perform
    end

    assert_equal 1, AcidicJob::Key.count
  end

  # def test_thing
  #   w = Worker.new
  #   w.perform rand(100)
  # end
end
