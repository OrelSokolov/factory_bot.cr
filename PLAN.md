# factory_bot.cr — порт factory_bot

> ⚠️ EXPERIMENTAL, DO NOT USE IN PRODUCTION YET.

Порт [thoughtbot/factory_bot](https://github.com/thoughtbot/factory_bot)
**6.5.6** на Crystal поверх active_record_cr. Оригинал вендорен в
`oracle/src` (полное дерево гема).

## Статус

**Готово, зелёное**: `crystal spec` — 56/56 оракул-кейсов.
`spec/oracle_spec.cr` воспроизводит `oracle/expected.yml` байт-в-байт:
кейсы сняты скриптом `oracle/cases.rb` с настоящего factory_bot 6.5.6
(AR 8.1.4 + SQLite in-memory) и повторяются портом на PostgreSQL
(идентичные значения, тексты ошибок, порядок колбэков, стратегии).

Требования: PostgreSQL, база `crails_factory_bot_test`
(`FACTORY_BOT_TEST_URL`, дефолт `postgres://root@/...?host=/var/run/postgresql`);
таблицы users/posts/accounts/tasks создаёт сам спек, модели читают
`db/schema.yml` (кодегенерация active_record_cr).

Регенерация оракула: `ruby oracle/cases.rb` → `oracle/expected.yml`
(значения записаны экранированными: `\n` — литеральные два символа;
spec разэкранирует при чтении).

## Что покрыто (56 кейсов)

- build / create (+ traits, overrides, блок, `*_list`, `*_pair`,
  block-with-index)
- attributes_for / attributes_for_list (ассоциации исключаются)
- build_stubbed (+ список, ассоциация с FK-заглушкой, кастомный
  `after(:stub)`, `Strategy::Stub.next_id=`)
- sequences: глобальные, inline, initial value, массивы значений,
  `generate`, `generate_list`, `rewind_sequences`, `FactoryBot.modify`
  (overridable-декларации)
- associations: parent strategy, `strategy: :build`, override объектом
  и FK (`user_id:` прерывает ассоциацию через алиасы), `aliases:`,
  `class:`, `use_parent_strategy`
- nested-фабрики (наследование атрибутов/класса от родителя)
- callbacks: before/after build/create/stub, глобальные callbacks,
  порядок; transient-атрибуты (не пишутся в запись, читаются из
  evaluator)
- initialize_with / to_create / skip_create
- traits_for_enum (`automatically_define_enum_traits` опционален)
- lint (валидные/невалидные фабрики, стратегия, текст ошибки)
- ошибки: неизвестная фабрика/трейт, дубликат фабрики/атрибута,
  самореференсная ассоциация/трейт — тексты 1:1 с гемом
- Syntax::Methods миксин

## Карта порта

| Оригинал (factory_bot/) | Порт (src/factory_bot/) |
|---|---|
| errors.rb | errors.cr |
| registry.rb (+ Decorator::DisallowsDuplicatesRegistry) | registry.cr |
| sequence.rb | sequence.cr |
| callback.rb, callbacks_observer.rb | callback.cr |
| attribute.rb, attribute/*.rb, declaration.rb, declaration/*.rb, attribute_list.rb, declaration_list.rb | attributes.cr |
| definition.rb, trait.rb, definition_hierarchy.rb | definition.cr |
| definition_proxy.rb | definition_proxy.cr |
| evaluator.rb, evaluator_class_definer.rb | evaluator.cr |
| attribute_assigner.rb (+ decorator/*.rb) | attribute_assigner.cr |
| evaluation.rb | evaluation.cr |
| strategy.rb, strategy/*.rb, factory_runner.rb | strategy.cr |
| factory.rb, null_factory.rb | factory.cr |
| enum.rb | enum.cr |
| linter.rb | linter.cr |
| internal.rb, configuration.rb | internal.cr |
| syntax/{default,methods}.rb | syntax.cr |

## Ключевые механики порта (Crystal 1.21)

- **DSL-блоки некапчурятся.** `FactoryBot.define`, `factory/trait/
  transient do ... end` идут через `with proxy yield` — неявные вызовы
  внутри биндятся на DefinitionProxy (замена `instance_eval`).
  Ленивые блоки (динамические атрибуты, sequence, callbacks,
  initialize_with, to_create) капчурятся только на прямых вызовах
  реальных def-методов — переадресация блока через method_missing
  в капчуренный контекст невозможна.
- **Сахар атрибутов** (`email { |e| ... }`, `admin`, `user factory: :x`)
  диспетчеризуется `macro method_missing` на DefinitionProxy: макрос
  генерирует перегрузку def под форму вызова (блок 0/1-арности →
  Proc-ограничение; без блока → `*args, **nargs`). Как и в factory_bot
  6.x, статические значения атрибутов не поддержаны — только блоки.
- **Evaluator** — хэш блоков вместо генерации классов
  (evaluator_class_definer): чтение атрибута `e.name` — через
  `macro method_missing` → `__read` с кэшем; трекинг вызовов
  (InvocationTracker) — множество имён.
- **Наследование атрибутов от родителя**: в геме — через иерархию
  сгенерированных evaluator-классов (`attribute_lists` родителя + свои);
  порт — `Factory#attributes` сливает `parent_factory.attributes` со
  своими (родительские первыми, дочерние перекрывают).
- **constantize**: `FactoryBot.__constantize` — macro finished
  справочник всех моделей active_record_cr (замена `String#constantize`).
- **Присвоение атрибутов**: вместо `public_send(:"#{attr}=", ...)` —
  `assign_attributes` + FK-эвристика (значение-модель и колонка
  `<name>_id` → внешний ключ, `<name>_type` → полиморфный тип), плюс
  кэш association target (`__cache_assoc`) — аналог Ruby `record.user =`,
  чтобы геттер возвращал несохранённую build-ассоциацию.
- **Int32 → Int64** при чтении атрибутов (таблицы active_record_cr
  декодируют целые как Int64); Symbol пишется в колонку как String.

## Отклонения от Ruby

- Возврат стратегий — union `Product` (`Base | Hash`): в колбэках/блоках
  нужен `.as(User)`; скалярный `id` — `Int64?`.
- `initialize_with { |e| e.new_instance }` вместо `initialize_with { new }`
  (нет self-диспетча на build_class внутри блока).
- `build_stubbed` не подменяет singleton-методы save/destroy (в Crystal
  их не переопределить на инстансе): ставит id/таймстемпы и
  `new_record=false`; `persisted?` у заглушки true.
- Linter печатает `RuntimeError` для исключений `raise "string"`
  (в Crystal это голый `Exception`; текст 1:1 с Ruby-выводом гема).
- `attributes_for` возвращает `Hash(String, FBValue)`, а не
  `Hash(Symbol, Object)`; ключи — строки.
- Вложенные фабрики регистрируются немедленно (в Ruby — отложенно,
  child_factories после родителя): uncapped yield требует выполнения
  блока на прокси ребёнка сразу. Семантически эквивалентно, т.к. parent
  разрешается по имени в момент run.
- Кастомные стратегии регистрируются через `FactoryBot.register_strategy`
  + `FactoryBot.run_strategy(name, ...)` (нет runtime-генерации методов
  StrategySyntaxMethodRegistrar).

## Обходы багов Crystal 1.21

- **`__fb_save!`/`__fb_save` кодеген на моделях**: вызов `save!` из
  `Proc(Base)` через виртуальный диспетч ломает nested-closure в
  `Base#save` (saved-флаг не материализуется). Поколенчески
  сгенерированные обёртки дают self статического типа модели.
- **Аннотированный сплат + `**nargs`** не матчит вызовы с нулём
  позиционных аргументов (`def x(*t : String, **n)` не вызывается как
  `x(name: 1)`), поэтому сплаты трейтов не аннотированы, а
  нормализация идёт в `__traits_a`/`__opts_hash`.

## Не портировано (не нужно для rails.cr-стека)

- syntax: make, shim (устаревшие синтаксисы)
- `FactoryBot.reload` есть, но file-scan (factories.rb/definitions) —
  вне скоупа (в Crystal определения в коде, не в файлах)
- `use_parent_strategy=false`-семантика для stub-стратегий частичная
  (stub всегда вызывает build_stubbed для ассоциаций, как в геме)
