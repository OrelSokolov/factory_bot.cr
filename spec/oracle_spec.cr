# Oracle spec: порт обязан воспроизвести oracle/expected.yml точно
# (снято с factory_bot 6.5.6 + AR 8.1.4 + SQLite in-memory). Те же ID
# кейсов; значения — тот же \n/\t-протокол. Адаптации к Crystal задокументи-
# рованы в PLAN.md (блоки с |e|, .as(Model) в колбэках/блоках и т.п.).

require "spec"
require "../src/factory_bot_cr"

EXPECTED = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/expected.yml").each_line do |line|
    if line.includes?('\t')
      id, value = line.split('\t', 2)
      hash[id] = unescape(value.chomp)
    end
  end
  hash
end

RESULTS = [] of {String, String}

def case!(id, value)
  RESULTS << {id, value.to_s}
end

def escape(s) : String
  s = s.to_s
  s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

# Обратное к esc из oracle/cases.rb (значения в expected.yml записаны
# экранированными: "\\n" — литеральные два символа).
def unescape(s) : String
  out = String::Builder.new
  i = 0
  while i < s.size
    if s[i] == '\\' && (n = s[i + 1]?)
      case n
      when '\\' then out << '\\'; i += 2
      when 'n'  then out << '\n'; i += 2
      when 't'  then out << '\t'; i += 2
      when 'r'  then out << '\r'; i += 2
      else out << s[i]; i += 1
      end
    else
      out << s[i]; i += 1
    end
  end
  out.to_s
end

# Нормализация значений (1:1 с oracle/cases.rb).
def norm(v) : String
  case v
  when String then v.inspect
  when Time   then "TIME"
  else v.to_s
  end
end

def ts(record, attr) : String
  record.attributes[attr]? ? "SET" : "nil"
end

def user_summary(u : User) : String
  "id=#{u.id ? "SET" : "nil"} name=#{u.name.inspect} email=#{u.email.inspect} " \
    "admin=#{u.admin.inspect} age=#{u.age.inspect} new_record=#{u.new_record?} " \
    "persisted=#{u.persisted?} created_at=#{ts(u, "created_at")}"
end

TEST_URL = ENV["FACTORY_BOT_TEST_URL"]? ||
           "postgres://root@/crails_factory_bot_test?host=/var/run/postgresql"

ActiveRecord::Base.establish_connection(TEST_URL)
conn = ActiveRecord::Base.__session
conn.exec(%(DROP TABLE IF EXISTS users))
conn.exec(%(CREATE TABLE IF NOT EXISTS users (
  id bigserial PRIMARY KEY, login varchar, name varchar, email varchar,
  admin bool, age int8, created_at timestamp, updated_at timestamp)))
conn.exec(%(CREATE TABLE IF NOT EXISTS posts (
  id bigserial PRIMARY KEY, title varchar, body text, user_id int8,
  published bool, created_at timestamp, updated_at timestamp)))
conn.exec(%(CREATE TABLE IF NOT EXISTS accounts (
  id bigserial PRIMARY KEY, name varchar, created_at timestamp, updated_at timestamp)))
conn.exec(%(CREATE TABLE IF NOT EXISTS tasks (
  id bigserial PRIMARY KEY, status varchar, created_at timestamp, updated_at timestamp)))
conn.exec(%(TRUNCATE users, posts, accounts, tasks RESTART IDENTITY))

class User < ActiveRecord::Base
end

class Post < ActiveRecord::Base
  belongs_to :user
end

class Account < ActiveRecord::Base
end

class Task < ActiveRecord::Base
end

module TagLog
  @@log = [] of String

  def self.<<(value : String)
    @@log << value
  end

  def self.log
    @@log
  end

  def self.clear
    @@log.clear
  end
end

FactoryBot.define do
  sequence(:email) { |n| "person#{n}@example.com" }
  sequence :counter, 100
  sequence :abbr, ["a", "b", "c"]

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
    admin
  end

  factory :subscriber, class: :user do
    email
    name { "Sub" }
  end

  factory :tagged, class: :user do
    name { "Tagged" }
    before(:build) { TagLog << "before_build" }
    after(:build) { |user| TagLog << "after_build:#{user.as(User).name}" }
    before(:create) { TagLog << "before_create" }
    after(:create) { |user, e| TagLog << "after_create:#{user.as(User).name}:#{e.age}" }
    after(:stub) { |user| user.as(User).age = 99 }
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
    initialize_with { |e|
      u = e.new_instance.as(User)
      u.name = "Ctor"
      u
    }
  end

  factory :no_save, class: :user do
    to_create { |instance| nil }
  end

  factory :skipped, class: :user do
    skip_create
  end

  factory :account do
    name { "Acme" }
  end

  factory :report, class: :post, aliases: ["article"] do
    title { "Report" }
  end

  factory :task do
    traits_for_enum :status, ["started", "finished"]
    status { "draft" }
  end
end

# --- 1. build / create --------------------------------------------------------

u = FactoryBot.build(:user).as(User)
case!("build_basic", user_summary(u))

u = FactoryBot.build(:user, name: "Ada", age: 7).as(User)
case!("build_override", "name=#{u.name.inspect} age=#{u.age.inspect} email=#{u.email.inspect}")

u = FactoryBot.create(:user).as(User)
case!("create_basic", user_summary(u))

u = FactoryBot.create(:user, :admin).as(User)
case!("create_trait", "name=#{u.name.inspect} admin=#{u.admin.inspect} age=#{u.age.inspect}")

u = FactoryBot.create(:user, :admin, :senior).as(User)
case!("create_traits_two", "admin=#{u.admin.inspect} age=#{u.age.inspect}")

u = FactoryBot.create(:user, :admin, name: "Grace").as(User)
case!("create_trait_override", "admin=#{u.admin.inspect} name=#{u.name.inspect} email=#{u.email.inspect}")

u = FactoryBot.create(:user) { |usr| usr.as(User).age = 77 }.as(User)
case!("create_block", "age=#{u.age.inspect} name=#{u.name.inspect}")

list = FactoryBot.build_list(:user, 2, :admin, name: "Listy").map(&.as(User))
case!("build_list", list.map { |x| "name=#{x.name} admin=#{x.admin} persisted=#{x.persisted?}" }.join(" | "))

list = FactoryBot.create_list(:user, 3).map(&.as(User))
case!("create_list", "count=#{list.size} persisted=#{list.all?(&.persisted?)} ages=#{list.map(&.age).join(',')}")

list = FactoryBot.create_list(:user, 2) { |usr, i| usr.as(User).age = 10 * i }.map(&.as(User))
case!("create_list_block_index", "ages=#{list.map(&.age).join(',')}")

pair = FactoryBot.create_pair(:account).map(&.as(Account))
case!("create_pair", "count=#{pair.size} names=#{pair.map(&.name).join(',')} persisted=#{pair.all?(&.persisted?)}")

# --- 2. attributes_for ----------------------------------------------------------

h = FactoryBot.attributes_for(:user)
case!("attributes_for", h.keys.sort.map { |k| "#{k}=#{norm(h[k])}" }.join(" "))

h = FactoryBot.attributes_for(:user, :admin, name: "X")
case!("attributes_for_trait_override", h.keys.sort.map { |k| "#{k}=#{norm(h[k])}" }.join(" "))

h = FactoryBot.attributes_for(:post)
case!("attributes_for_assoc_excluded", h.keys.sort.map { |k| "#{k}=#{norm(h[k])}" }.join(" "))

list = FactoryBot.attributes_for_list(:account, 2)
case!("attributes_for_list", "count=#{list.size} first_name=#{list.first["name"].inspect}")

# --- 3. build_stubbed -----------------------------------------------------------

u = FactoryBot.build_stubbed(:user).as(User)
case!("build_stubbed", "id=#{u.id} persisted=#{u.persisted?} new_record=#{u.new_record?} " \
  "destroyed=#{u.destroyed?} created_at=#{ts(u, "created_at")} name=#{u.name.inspect}")

us = FactoryBot.build_stubbed_list(:user, 2).map(&.as(User))
case!("build_stubbed_list", us.map { |x| "id=#{x.id}" }.join(" "))

p = FactoryBot.build_stubbed(:post).as(Post)
case!("build_stubbed_assoc", "post_id=#{p.id} user_id=#{p.user_id} " \
  "fk_is_stub_id=#{!p.user_id.nil? && p.user_id.not_nil! > 1000} published=#{p.published.inspect}")

u = FactoryBot.build_stubbed(:tagged).as(User)
case!("build_stubbed_custom_callback", "age=#{u.age.inspect} name=#{u.name.inspect}")

FactoryBot::Strategy::Stub.next_id = 5000
u = FactoryBot.build_stubbed(:user).as(User)
case!("stub_next_id_setter", "id=#{u.id}")
FactoryBot::Strategy::Stub.next_id = 1000

# --- 4. sequences -----------------------------------------------------------------

case!("sequence_global", "#{FactoryBot.generate(:email)} #{FactoryBot.generate(:email)}")
FactoryBot.rewind_sequences
case!("sequence_rewind", FactoryBot.generate(:email))
case!("sequence_initial_value", "#{FactoryBot.generate(:counter)} #{FactoryBot.generate(:counter)}")
case!("sequence_array", "#{FactoryBot.generate(:abbr)} #{FactoryBot.generate(:abbr)} #{FactoryBot.generate(:abbr)}")
FactoryBot.rewind_sequences
case!("generate_list", FactoryBot.generate_list(:abbr, 2).map(&.to_s).join(","))

FactoryBot.modify do
  factory :subscriber do
    sequence(:login) { |n| "login#{n}" }
    name { "ModSub" }
  end
end
s1 = FactoryBot.create(:subscriber).as(User)
s2 = FactoryBot.create(:subscriber).as(User)
case!("inline_sequence_and_modify", "logins=#{s1.login.inspect},#{s2.login.inspect} name=#{s1.name.inspect}")

u = FactoryBot.create(:admin_only).as(User)
case!("implicit_trait_attr", "admin=#{u.admin.inspect} name=#{u.name.inspect} age=#{u.age.inspect}")

s = FactoryBot.create(:subscriber, name: "S2").as(User)
case!("implicit_sequence_attr", "email=#{s.email.inspect} name=#{s.name.inspect}")

# --- 5. associations -----------------------------------------------------------------

p = FactoryBot.create(:post).as(Post)
user = p.user.not_nil!
case!("assoc_create", "title=#{p.title.inspect} persisted=#{p.persisted?} " \
  "user_id_set=#{!p.user_id.nil?} fk_matches=#{p.user_id == user.id} " \
  "user_persisted=#{user.persisted?} user_name=#{user.name.inspect}")

p = FactoryBot.build(:post).as(Post)
user = p.user.not_nil!
case!("assoc_build_parent_strategy", "persisted=#{p.persisted?} user_id=#{p.user_id.inspect} " \
  "user_name=#{user.name.inspect} user_persisted=#{user.persisted?}")

existing = FactoryBot.create(:user, name: "Existing").as(User)
p = FactoryBot.create(:post, user: existing).as(Post)
case!("assoc_override_object", "user_name=#{p.user.not_nil!.name.inspect} fk_matches=#{p.user_id == existing.id}")

p = FactoryBot.create(:post, user_id: 555).as(Post)
case!("assoc_override_fk_alias", "user_id=#{p.user_id.inspect} user_nil=#{p.user.nil?}")

p = FactoryBot.build(:draft).as(Post)
user = p.user.not_nil!
case!("assoc_strategy_build", "persisted=#{p.persisted?} user_id=#{p.user_id.inspect} " \
  "user_new_record=#{user.new_record?} user_name=#{user.name.inspect}")

p = FactoryBot.create(:post, :published).as(Post)
case!("assoc_with_trait", "published=#{p.published.inspect} title=#{p.title.inspect}")

p = FactoryBot.create(:report, title: "R").as(Post)
case!("aliases_and_class", "class=#{p.class} title=#{p.title.inspect} persisted=#{p.persisted?}")

# --- 6. наследование -----------------------------------------------------------------

u = FactoryBot.create(:active_user).as(User)
case!("nested_child_factory", "name=#{u.name.inspect} age=#{u.age.inspect} email=#{u.email.inspect}")

FactoryBot.use_parent_strategy = false
p = FactoryBot.build(:post).as(Post)
FactoryBot.use_parent_strategy = true
case!("use_parent_strategy_off", "post_persisted=#{p.persisted?} user_created=#{p.user.not_nil!.persisted?} " \
  "fk_assigned=#{!p.user_id.nil?}")

# --- 7. callbacks --------------------------------------------------------------------

TagLog.clear
FactoryBot.create(:tagged)
case!("callbacks_order", TagLog.log.join(","))

TagLog.clear
u = FactoryBot.build_stubbed(:tagged).as(User)
case!("callback_after_stub_fires", "log=#{TagLog.log.join(',')} age=#{u.age.inspect}")

u = FactoryBot.create(:user, dates: true).as(User)
case!("transient_in_record_not_assigned", "name=#{u.name.inspect} " \
  "responds_to_dates=#{u.class.__column_names.includes?("dates")}")

u = FactoryBot.create(:guest).as(User)
case!("initialize_with", "name=#{u.name.inspect} age=#{u.age.inspect} email=#{u.email.inspect}")

u = FactoryBot.create(:no_save).as(User)
case!("to_create_custom", "persisted=#{u.persisted?} new_record=#{u.new_record?} id=#{u.id.inspect}")

u = FactoryBot.create(:skipped).as(User)
case!("skip_create", "persisted=#{u.persisted?} new_record=#{u.new_record?}")

u = FactoryBot.build(:guest).as(User)
case!("initialize_with_build", "name=#{u.name.inspect} persisted=#{u.persisted?}")

# --- 8. enum traits -----------------------------------------------------------------

t = FactoryBot.create(:task, :started).as(Task)
case!("enum_trait_started", "status=#{t.status.inspect} persisted=#{t.persisted?}")
t = FactoryBot.create(:task, :finished).as(Task)
case!("enum_trait_finished", "status=#{t.status.inspect}")

# --- 9. глобальные callbacks / lint ---------------------------------------------------

FactoryBot.define do
  after(:create) { |record| record.as(User).email = "global@example.com" }
end
u = FactoryBot.create(:user).as(User)
case!("global_callback", "email=#{u.email.inspect} name=#{u.name.inspect}")

begin
  FactoryBot.lint([FactoryBot.factories.find("account")], false, false, "build")
  case!("lint_ok", "ok")
rescue e : FactoryBot::InvalidFactoryError
  case!("lint_ok", "error:#{e.class}: #{e.message}")
end

FactoryBot.define do
  factory :broken, class: :account do
    to_create { |instance| raise "boom" }
  end
end
begin
  FactoryBot.lint([FactoryBot.factories.find("broken")], false, false, "create")
  case!("lint_invalid", "ok")
rescue e : FactoryBot::InvalidFactoryError
  case!("lint_invalid", e.message)
end

# --- 10. ошибки ----------------------------------------------------------------------

begin
  FactoryBot.create(:nope)
rescue e
  case!("error_unknown_factory", "#{e.class}: #{e.message}")
end

begin
  FactoryBot.define { factory :user }
rescue e
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
rescue e
  case!("error_attribute_redefined", "#{e.class}: #{e.message}")
end

begin
  FactoryBot.create(:user, :unknown_trait)
rescue e
  case!("error_unknown_trait", "#{e.class}: #{e.message}")
end

begin
  FactoryBot.define do
    factory :selfref, class: :account do
      association :selfref
    end
  end
  FactoryBot.create(:selfref)
rescue e
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
rescue e
  case!("error_self_referencing_trait", "#{e.class}: #{e.message}")
end

# --- 11. Syntax::Methods миксин --------------------------------------------------------

class MyTestContext
  include FactoryBot::Syntax::Methods
end

ctx = MyTestContext.new
u = ctx.build(:user).not_nil!.as(User)
case!("syntax_methods_mixin", "name=#{u.name.inspect} age=#{u.age.inspect}")

# --- Сверка с oracle --------------------------------------------------------------------

describe "factory_bot_cr oracle replay" do
  it "reproduces oracle/expected.yml exactly (#{RESULTS.size} cases)" do
    missing = [] of String
    EXPECTED.each do |id, expected_value|
      found = RESULTS.find { |rid, _| rid == id }
      if found.nil?
        missing << id
      elsif (found_value = found[1]) != expected_value
        fail("case #{id}:\n  oracle: #{escape(expected_value)}\n  port:   #{escape(found_value)}")
      end
    end
    extra = RESULTS.reject { |rid, _| EXPECTED.has_key?(rid) }.map(&.[0])
    fail("missing cases: #{missing.join(", ")}") unless missing.empty?
    fail("extra cases: #{extra.join(", ")}") unless extra.empty?
  end
end
