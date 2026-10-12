# frozen_string_literal: true

# Oracle-кейсы factory_bot 6.5.6 (vendored в ./src) поверх ActiveRecord
# 8.1.4 + SQLite in-memory. Запуск: `ruby oracle/cases.rb` → expected.yml.
# Crystal-порт (spec/oracle_spec.cr) обязан воспроизвести каждый кейс
# (те же ID, те же значения; таблица ids/времени нормализованы — PG-шные
# sequence gaps после rollback не должны влиять).

require "active_record"
require "factory_bot"

$LOAD_PATH.unshift File.expand_path("../src/lib", __dir__)

RESULTS = []

def case!(id, value)
  RESULTS << [id, value.to_s]
end

def esc(s)
  s.to_s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

# Нормализация значений: строки в хэшах — inspect, прочее — to_s;
# Time → TIME (значения не детерминированы).
def norm(v)
  case v
  when String then v.inspect
  when Time, ActiveSupport::TimeWithZone then "TIME"
  else v.to_s
  end
end

def ts(record, attr) # таймстемп → SET/nil
  record.send(attr) ? "SET" : "nil"
end

def user_summary(u)
  "id=#{u.id ? 'SET' : 'nil'} name=#{u.name.inspect} email=#{u.email.inspect} " \
    "admin=#{u.admin.inspect} age=#{u.age.inspect} new_record=#{u.new_record?} " \
    "persisted=#{u.persisted?} created_at=#{ts(u, :created_at)}"
end

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.define(version: 1) do
  create_table :users do |t|
    t.string :login
    t.string :name
    t.string :email
    t.boolean :admin
    t.integer :age
    t.timestamps
  end
  create_table :posts do |t|
    t.string :title
    t.text :body
    t.references :user
    t.boolean :published
    t.timestamps
  end
  create_table :accounts do |t|
    t.string :name
    t.timestamps
  end
  create_table :tasks do |t|
    t.string :status
    t.timestamps
  end
end

class User < ActiveRecord::Base; end
class Post < ActiveRecord::Base
  belongs_to :user
end
class Account < ActiveRecord::Base; end
class Task < ActiveRecord::Base; end

FactoryBot.define do
  sequence(:email) { |n| "person#{n}@example.com" }
  sequence :counter, 100
  sequence :abbr, %w[a b c].each

  trait :admin do
    admin { true }
    age { 30 }
  end

  trait :senior do
    age { 70 }
  end

  factory :user do
    name { "John" }
    email { |e| "#{e.name}@example.com".downcase }
    age { 42 }
    admin { false }

    transient do
      dates { false }
    end

    factory :active_user do
      age { 25 }
    end
  end

  factory :admin_only, class: :user do
    admin # implicit trait из :user (defined_traits наследуются)
  end

  factory :subscriber, class: :user do
    email # implicit → глобальная sequence :email
    name { "Sub" }
  end

  factory :tagged, class: :user do
    name { "Tagged" }
    before(:build) { TagLog << "before_build" }
    after(:build) { |user| TagLog << "after_build:#{user.name}" }
    before(:create) { TagLog << "before_create" }
    after(:create) { |user, e| TagLog << "after_create:#{user.name}:#{e.age}" }
    after(:stub) { |user| user.age = 99 }
  end

  factory :post do
    title { "Post" }
    body { "Body" }
    published { false }
    association :user
    trait :published do
      published { true }
    end
  end

  factory :draft, class: :post do
    association :user, strategy: :build
  end

  factory :guest, class: :user do
    initialize_with { new(name: "Ctor") }
  end

  factory :no_save, class: :user do
    to_create { |instance| }
  end

  factory :skipped, class: :user do
    skip_create
  end

  factory :account do
    name { "Acme" }
  end

  factory :report, class: :post, aliases: [:article] do
    title { "Report" }
  end

  factory :task do
    traits_for_enum :status, %w[started finished]
    status { "draft" }
  end
end

module TagLog
  def self.log; @log ||= []; end
  def self.<<(v); log << v; end
end

# --- 1. build / create ------------------------------------------------------

u = FactoryBot.build(:user)
case!("build_basic", user_summary(u))

u = FactoryBot.build(:user, name: "Ada", age: 7)
case!("build_override", "name=#{u.name.inspect} age=#{u.age.inspect} email=#{u.email.inspect}")

u = FactoryBot.create(:user)
case!("create_basic", user_summary(u))

u = FactoryBot.create(:user, :admin)
case!("create_trait", "name=#{u.name.inspect} admin=#{u.admin.inspect} age=#{u.age.inspect}")

u = FactoryBot.create(:user, :admin, :senior)
case!("create_traits_two", "admin=#{u.admin.inspect} age=#{u.age.inspect}")

u = FactoryBot.create(:user, :admin, name: "Grace")
case!("create_trait_override", "admin=#{u.admin.inspect} name=#{u.name.inspect} email=#{u.email.inspect}")

u = FactoryBot.create(:user) { |usr| usr.age = 77 }
case!("create_block", "age=#{u.age.inspect} name=#{u.name.inspect}")

list = FactoryBot.build_list(:user, 2, :admin, name: "Listy")
case!("build_list", list.map { |x| "name=#{x.name} admin=#{x.admin} persisted=#{x.persisted?}" }.join(" | "))

list = FactoryBot.create_list(:user, 3)
case!("create_list", "count=#{list.size} persisted=#{list.all?(&:persisted?)} ages=#{list.map(&:age).join(',')}")

list = FactoryBot.create_list(:user, 2) { |usr, i| usr.age = 10 * i }
case!("create_list_block_index", "ages=#{list.map(&:age).join(',')}")

pair = FactoryBot.create_pair(:account)
case!("create_pair", "count=#{pair.size} names=#{pair.map(&:name).join(',')} persisted=#{pair.all?(&:persisted?)}")

# --- 2. attributes_for ------------------------------------------------------

h = FactoryBot.attributes_for(:user)
case!("attributes_for", h.sort.map { |k, v| "#{k}=#{norm(v)}" }.join(" "))

h = FactoryBot.attributes_for(:user, :admin, name: "X")
case!("attributes_for_trait_override", h.sort.map { |k, v| "#{k}=#{norm(v)}" }.join(" "))

h = FactoryBot.attributes_for(:post)
case!("attributes_for_assoc_excluded", h.sort.map { |k, v| "#{k}=#{norm(v)}" }.join(" "))

list = FactoryBot.attributes_for_list(:account, 2)
case!("attributes_for_list", "count=#{list.size} first_name=#{list.first[:name].inspect}")

# --- 3. build_stubbed -------------------------------------------------------

u = FactoryBot.build_stubbed(:user)
case!("build_stubbed", "id=#{u.id} persisted=#{u.persisted?} new_record=#{u.new_record?} " \
  "destroyed=#{u.destroyed?} created_at=#{ts(u, :created_at)} name=#{u.name.inspect}")

us = FactoryBot.build_stubbed_list(:user, 2)
case!("build_stubbed_list", us.map { |x| "id=#{x.id}" }.join(" "))

p = FactoryBot.build_stubbed(:post)
case!("build_stubbed_assoc", "post_id=#{p.id} user_id=#{p.user_id} " \
  "fk_is_stub_id=#{p.user_id.to_i > 1000} published=#{p.published.inspect}")

u = FactoryBot.build_stubbed(:tagged)
case!("build_stubbed_custom_callback", "age=#{u.age.inspect} name=#{u.name.inspect}")

FactoryBot::Strategy::Stub.next_id = 5000
u = FactoryBot.build_stubbed(:user)
case!("stub_next_id_setter", "id=#{u.id}")
FactoryBot::Strategy::Stub.next_id = 1000

# --- 4. sequences ------------------------------------------------------------

case!("sequence_global", "#{FactoryBot.generate(:email)} #{FactoryBot.generate(:email)}")
FactoryBot.rewind_sequences
case!("sequence_rewind", FactoryBot.generate(:email))
case!("sequence_initial_value", "#{FactoryBot.generate(:counter)} #{FactoryBot.generate(:counter)}")
case!("sequence_array", "#{FactoryBot.generate(:abbr)} #{FactoryBot.generate(:abbr)} #{FactoryBot.generate(:abbr)}")
FactoryBot.rewind_sequences
case!("generate_list", FactoryBot.generate_list(:abbr, 2).join(","))

FactoryBot.modify do
  factory :subscriber do
    sequence(:login) { |n| "login#{n}" }
    name { "ModSub" }
  end
end
s1 = FactoryBot.create(:subscriber)
s2 = FactoryBot.create(:subscriber)
case!("inline_sequence_and_modify", "logins=#{s1.login.inspect},#{s2.login.inspect} name=#{s1.name.inspect}")

u = FactoryBot.create(:admin_only)
case!("implicit_trait_attr", "admin=#{u.admin.inspect} name=#{u.name.inspect} age=#{u.age.inspect}")

s = FactoryBot.create(:subscriber, name: "S2")
case!("implicit_sequence_attr", "email=#{s.email.inspect} name=#{s.name.inspect}")

# --- 5. associations ---------------------------------------------------------

p = FactoryBot.create(:post)
case!("assoc_create", "title=#{p.title.inspect} persisted=#{p.persisted?} " \
  "user_id_set=#{!p.user_id.nil?} fk_matches=#{p.user_id == p.user.id} " \
  "user_persisted=#{p.user.persisted?} user_name=#{p.user.name.inspect}")

p = FactoryBot.build(:post)
case!("assoc_build_parent_strategy", "persisted=#{p.persisted?} user_id=#{p.user_id.inspect} " \
  "user_name=#{p.user.name.inspect} user_persisted=#{p.user.persisted?}")

existing = FactoryBot.create(:user, name: "Existing")
p = FactoryBot.create(:post, user: existing)
case!("assoc_override_object", "user_name=#{p.user.name.inspect} fk_matches=#{p.user_id == existing.id}")

p = FactoryBot.create(:post, user_id: 555)
case!("assoc_override_fk_alias", "user_id=#{p.user_id.inspect} user_nil=#{p.user.nil?}")

p = FactoryBot.build(:draft)
case!("assoc_strategy_build", "persisted=#{p.persisted?} user_id=#{p.user_id.inspect} " \
  "user_new_record=#{p.user.new_record?} user_name=#{p.user.name.inspect}")

p = FactoryBot.create(:post, :published)
case!("assoc_with_trait", "published=#{p.published.inspect} title=#{p.title.inspect}")

p = FactoryBot.create(:report, title: "R")
case!("aliases_and_class", "class=#{p.class.name} title=#{p.title.inspect} persisted=#{p.persisted?}")

# --- 6. наследование/вложенные фабрики ---------------------------------------

u = FactoryBot.create(:active_user)
case!("nested_child_factory", "name=#{u.name.inspect} age=#{u.age.inspect} email=#{u.email.inspect}")

FactoryBot.use_parent_strategy = false
p = FactoryBot.build(:post)
FactoryBot.use_parent_strategy = true
case!("use_parent_strategy_off", "post_persisted=#{p.persisted?} user_created=#{p.user.persisted?} " \
  "fk_assigned=#{!p.user_id.nil?}")

# --- 7. callbacks -------------------------------------------------------------

TagLog.log.clear
FactoryBot.create(:tagged)
case!("callbacks_order", TagLog.log.join(","))

TagLog.log.clear
u = FactoryBot.build_stubbed(:tagged)
case!("callback_after_stub_fires", "log=#{TagLog.log.join(',')} age=#{u.age.inspect}")

u = FactoryBot.create(:user, dates: true)
case!("transient_in_record_not_assigned", "name=#{u.name.inspect} " \
  "responds_to_dates=#{u.respond_to?(:dates)}")

u = FactoryBot.create(:guest)
case!("initialize_with", "name=#{u.name.inspect} age=#{u.age.inspect} email=#{u.email.inspect}")

u = FactoryBot.create(:no_save)
case!("to_create_custom", "persisted=#{u.persisted?} new_record=#{u.new_record?} id=#{u.id.inspect}")

u = FactoryBot.create(:skipped)
case!("skip_create", "persisted=#{u.persisted?} new_record=#{u.new_record?}")

u = FactoryBot.build(:guest)
case!("initialize_with_build", "name=#{u.name.inspect} persisted=#{u.persisted?}")

# --- 8. enum traits -----------------------------------------------------------

t = FactoryBot.create(:task, :started)
case!("enum_trait_started", "status=#{t.status.inspect} persisted=#{t.persisted?}")
t = FactoryBot.create(:task, :finished)
case!("enum_trait_finished", "status=#{t.status.inspect}")

# --- 9. глобальные callbacks / lint --------------------------------------------

FactoryBot.define do
  after(:create) { |record| record.email = "global@example.com" }
end
u = FactoryBot.create(:user)
case!("global_callback", "email=#{u.email.inspect} name=#{u.name.inspect}")

begin
  FactoryBot.lint([FactoryBot.factories.find(:account)], strategy: :build)
  case!("lint_ok", "ok")
rescue FactoryBot::InvalidFactoryError => e
  case!("lint_ok", "error:#{e.class}: #{e.message}")
end

FactoryBot.define do
  factory :broken, class: :account do
    to_create { |instance| raise "boom" }
  end
end
begin
  FactoryBot.lint([FactoryBot.factories.find(:broken)], strategy: :create)
  case!("lint_invalid", "ok")
rescue FactoryBot::InvalidFactoryError => e
  case!("lint_invalid", e.message.gsub(/0x[0-9a-f]+/, "0xX"))
end

# --- 10. ошибки ---------------------------------------------------------------

begin
  FactoryBot.create(:nope)
rescue => e
  case!("error_unknown_factory", "#{e.class}: #{e.message}")
end

begin
  FactoryBot.define { factory :user }
rescue => e
  case!("error_duplicate_factory", "#{e.class}: #{e.message}")
end

begin
  FactoryBot.define do
    factory :dup_attr, class: :account do
      name { "a" }
      name { "b" }
    end
  end
  FactoryBot.attributes_for(:dup_attr)
rescue => e
  case!("error_attribute_redefined", "#{e.class}: #{e.message}")
end

begin
  FactoryBot.create(:user, :unknown_trait)
rescue => e
  case!("error_unknown_trait", "#{e.class}: #{e.message}")
end

begin
  FactoryBot.define do
    factory :selfref, class: :account do
      association :selfref
    end
  end
  FactoryBot.create(:selfref)
rescue => e
  case!("error_self_referencing_association", "#{e.class}: #{e.message}")
end

begin
  FactoryBot.define do
    factory :selftrait, class: :account do
      trait :looping do
        looping
      end
    end
  end
  FactoryBot.create(:selftrait, :looping)
rescue => e
  case!("error_self_referencing_trait", "#{e.class}: #{e.message}")
end

# --- 11. Syntax::Methods миксин ------------------------------------------------

class MyTestContext
  include FactoryBot::Syntax::Methods
end
ctx = MyTestContext.new
u = ctx.build(:user)
case!("syntax_methods_mixin", "name=#{u.name.inspect} age=#{u.age.inspect}")

# --- запись expected.yml --------------------------------------------------------

File.open(File.expand_path("expected.yml", __dir__), "w") do |f|
  RESULTS.each do |id, value|
    f.puts("#{id}\t#{esc(value)}")
  end
end

puts "Wrote #{RESULTS.size} cases to expected.yml"
