# factory_bot.cr

A Crystal port of [thoughtbot/factory_bot](https://github.com/thoughtbot/factory_bot)
**6.5.6** on top of `active_record.cr` — test fixtures with factories,
traits, sequences, callbacks and strategies. The original gem tree is
vendored in `oracle/src`; behavior is replayed 1:1 from an oracle
recorded with the real factory_bot 6.5.6 (AR 8.1.4 + SQLite) against
PostgreSQL: identical values, error texts, callback order and strategies.

> ⚠️ EXPERIMENTAL — DO NOT USE IN PRODUCTION YET.

## Installation

```yaml
dependencies:
  factory_bot_cr:
    github: OrelSokolov/factory_bot.cr
```

```sh
shards install
```

Requires PostgreSQL (test DB `crails_factory_bot_test`, override with
`FACTORY_BOT_TEST_URL`); tables are created by the specs themselves.

## Usage

```crystal
require "factory_bot_cr"
include FactoryBot::Syntax::Methods

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "secret" }
  end

  factory :post do
    title { "A post" }
    user factory: :user
    trait :published do
      published { true }
    end
  end
end

user = create(:user)
posts = create_list(:post, 3, :published, user: user)
stub  = build_stubbed(:post)
attrs = attributes_for(:post)
```

## Feature comparison vs factory_bot 6.5.6

### Strategies & building

| Feature | Original (factory_bot) | Port (factory_bot.cr) | Status |
|---|---|---|---|
| `build` / `create` (+ traits, overrides, block, `*_list`, `*_pair`, block-with-index) | ✅ | Same | ✅ |
| `attributes_for` / `attributes_for_list` (associations excluded) | ✅ | Returns `Hash(String, FBValue)` with String keys (Ruby: `Hash(Symbol, Object)`) | 🔶 |
| `build_stubbed` (+ list, FK stub association, custom `after(:stub)`, `Strategy::Stub.next_id=`) | ✅ | Sets id/timestamps and `new_record=false` (`persisted?` → true); cannot replace singleton save/destroy methods on an instance in Crystal | 🔶 |
| `initialize_with` / `to_create` / `skip_create` | ✅ | `initialize_with { \|e\| e.new_instance }` (no self-dispatch on build_class inside the block) | 🔶 |
| Custom strategies | `register_strategy` + generated syntax methods | `FactoryBot.register_strategy` + `FactoryBot.run_strategy(name, ...)` (no runtime method generation) | 🔶 |

### Definitions

| Feature | Original | Port | Status |
|---|---|---|---|
| Sequences: global, inline, initial value, value arrays, `generate`, `generate_list`, `rewind_sequences`, `FactoryBot.modify` | ✅ | Same | ✅ |
| Associations: parent strategy, `strategy: :build`, object and FK overrides (`user_id:`), `aliases:`, `class:`, `use_parent_strategy` | ✅ | Attribute assignment via `assign_attributes` + FK heuristics (`<name>_id` → FK, `<name>_type` → polymorphic type) + association target cache | ✅ |
| Nested factories (attribute/class inheritance from parent) | ✅ | Registered immediately (Ruby defers child_factories); parent resolves by name at run — semantically equivalent | 🔶 |
| Traits, `traits_for_enum` (`automatically_define_enum_traits` optional) | ✅ | Same | ✅ |
| Callbacks: before/after build/create/stub, global callbacks, ordering; transient attributes (not written to the record, read from evaluator) | ✅ | Same | ✅ |
| Static attribute values (`email "x"`, no block) | not supported in 6.x | Also unsupported — blocks only | ✅ |
| Lint (valid/invalid factories, strategy, error text) | ✅ | Prints `RuntimeError` for `raise "string"` exceptions (bare `Exception` in Crystal; text 1:1) | 🔶 |
| Errors: unknown factory/trait, duplicate factory/attribute, self-referencing association/trait | ✅ | Texts 1:1 with the gem | ✅ |
| `Syntax::Methods` mixin | ✅ | Same | ✅ |
| `make`/`shim` legacy syntaxes, file-scan of definitions | ✅ | Not ported (definitions live in code in Crystal) | ❌ |

## Deviations & Crystal-specific notes

- DSL blocks (`FactoryBot.define`, `factory/trait/transient do ... end`)
  run through a proxy `yield` instead of `instance_eval`; attribute sugar
  (`email { |e| ... }`, `admin`, `user factory: :x`) dispatches through a
  `macro method_missing` on the DefinitionProxy.
- Strategy results are a `Product` union (`Base | Hash`) — callbacks and
  blocks need `.as(User)`; the scalar `id` is `Int64?`.
- Evaluator is a hash of blocks instead of generated evaluator classes;
  parent attributes are merged by `Factory#attributes`.
- `constantize` is replaced by a compile-time registry of all
  active_record.cr models (`macro finished`).
- Int32 → Int64 coercion when reading attributes; Symbols are written to
  columns as Strings.

## Testing

```sh
crystal spec   # 56/56 oracle cases
```

`spec/oracle_spec.cr` reproduces `oracle/expected.yml` byte-for-byte.
Regenerate with `ruby oracle/cases.rb > oracle/expected.yml` (values are
escaped: `\n` is two literal characters, unescaped by the spec).
