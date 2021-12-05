# frozen_string_literal: true

require "active_record"
require "global_id"
require "minitest/mock"
require "logger"
require "sqlite3"

# DATABASE AND MODELS ----------------------------------------------------------
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: "test/database.sqlite",
  flags: SQLite3::Constants::Open::READWRITE |
         SQLite3::Constants::Open::CREATE |
         SQLite3::Constants::Open::SHAREDCACHE
)

GlobalID.app = :test

# rubocop:disable Metrics/BlockLength
ActiveRecord::Schema.define do
  create_table :acidic_job_keys, force: true do |t|
    t.string :idempotency_key, null: false
    t.string :job_name, null: false
    t.text :job_args, null: true
    t.datetime :last_run_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    t.datetime :locked_at, null: true
    t.string :recovery_point, null: false
    t.text :error_object
    t.text :attr_accessors
    t.text :workflow
    t.text :serialized_job, null: true
    t.timestamps

    t.index %i[idempotency_key job_name job_args], unique: true,
                                                   name: "idx_acidic_job_keys_on_idempotency_key_n_job_name_n_job_args"
  end

  create_table :staged_acidic_jobs, force: true do |t|
    t.string :adapter, null: false
    t.string :job_name, null: false
    t.text :job_args, null: true
  end

  create_table :audits, force: true do |t|
    t.references :auditable, polymorphic: true
    t.references :associated, polymorphic: true
    t.references :user, polymorphic: true
    t.string :username
    t.string :action
    t.text :audited_changes
    t.integer :version, default: 0
    t.string :comment
    t.string :remote_address
    t.string :request_uuid
    t.timestamps

    t.index %i[auditable_type auditable_id version]
    t.index %i[associated_type associated_id]
    t.index %i[user_id user_type]
    t.index :request_uuid
  end

  create_table :users, force: true do |t|
    t.string :email, null: false
    t.string :stripe_customer_id, null: false
    t.timestamps
  end

  create_table :rides, force: true do |t|
    t.integer :origin_lat
    t.integer :origin_lon
    t.integer :target_lat
    t.integer :target_lon
    t.string :stripe_charge_id
    t.references :user, foreign_key: true, on_delete: :restrict
    t.timestamps
  end
end
# rubocop:enable Metrics/BlockLength

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  include GlobalID::Identification
end

class Audit < ApplicationRecord
  belongs_to :auditable, polymorphic: true
  belongs_to :associated, polymorphic: true
  belongs_to :user, polymorphic: true
end

class User < ApplicationRecord
  validates :email, presence: true
  validates :stripe_customer_id, presence: true
end

class Ride < ApplicationRecord
  belongs_to :user
end

require "database_cleaner/active_record"
DatabaseCleaner.strategy = [:deletion, { except: %w[users] }]
DatabaseCleaner.clean

# SEEDS ------------------------------------------------------------------------

USERS = [
  ["user@example.com", "tok_visa"],
  ["user-bad-source@example.com", "tok_chargeCustomerFail"]
].freeze

USERS.each do |(email, stripe_source)|
  User.create!(email: email,
               stripe_customer_id: stripe_source)
end

# LOGGING ----------------------------------------------------------------------

ActiveRecord::Base.logger = Logger.new(IO::NULL) # Logger.new($stdout) #

# MOCKS ------------------------------------------------------------------------

module Stripe
  class CardError < StandardError; end

  class StripeError < StandardError; end

  class Charge
    def self.create(params, _args)
      raise CardError, "Your card was declined." if params[:customer] == "tok_chargeCustomerFail"

      charge_struct = Struct.new(:id)
      charge_struct.new(123)
    end
  end
end
