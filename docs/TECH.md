# Reactor Control v2 — техническая документация

Документ для разработчика (для себя в будущем): как устроена программа, что делает каждый модуль,
какие у него функции и как всё это менять, не перечитывая код целиком.

Содержание:

1. [Коротко об архитектуре](#1-коротко-об-архитектуре)
2. [Файлы: репозиторий и установка в игре](#2-файлы-репозиторий-и-установка-в-игре)
3. [Запуск и главный цикл](#3-запуск-и-главный-цикл)
4. [core — ядро](#4-core--ядро)
5. [hw — работа с железом](#5-hw--работа-с-железом)
6. [logic — защита и замеры](#6-logic--защита-и-замеры)
7. [net — интернет и GitHub](#7-net--интернет-и-github)
8. [commands — чат-команды](#8-commands--чат-команды)
9. [ui — интерфейс](#9-ui--интерфейс)
10. [Внешние библиотеки](#10-внешние-библиотеки)
11. [Факты о реальном железе (HiTech, ME, Flux)](#11-факты-о-реальном-железе-hitech-me-flux)
12. [Установщик, обновление, переход с v1](#12-установщик-обновление-переход-с-v1)
13. [Файлы, которые правятся на GitHub без выпуска версии](#13-файлы-которые-правятся-на-github-без-выпуска-версии)
14. [Как выпустить новую версию](#14-как-выпустить-новую-версию)
15. [Тесты, эмулятор, зонд](#15-тесты-эмулятор-зонд)
16. [Рецепты: как добавить …](#16-рецепты-как-добавить-)
17. [Грабли (то, на что уже наступали)](#17-грабли-то-на-что-уже-наступали)

---

## 1. Коротко об архитектуре

Одна программа, один поток, один цикл событий. Никаких `os.sleep`, `thread` и параллельных таймеров.

```
           ┌────────────── App (core/app.lua) ───────────────┐
 event.pull│  Scheduler: задачи опроса по расписанию          │
 ─────────►│   coolant/protect/running/stats/rods/static/...  │
 touch,key,│        │                                         │
 chat,     │        ▼                                         │
 component │  hw/*  ── читают железо ──► State (core/state)   │
           │                               │   ▲             │
           │  logic/protection.evaluate ◄──┘   │ пишет       │
           │        │ команды stop/start          │             │
           │        ▼                           │             │
           │  core/actions ── activate/deactivate + журнал    │
           │                                                  │
           │  onFrame ─► ui/ui (GUI) или ui/textui (TUI)      │
           │             только ЧИТАЮТ State и вызывают        │
           │             app.actions:* по нажатиям            │
           └──────────────────────────────────────────────────┘
```

Главные правила, на которых всё держится:

- **Логика не знает про интерфейс.** `hw`, `logic`, `core` ничего не рисуют. Интерфейс ничего не опрашивает —
  только читает `app.state`, `app.cfg`, `app.log` и вызывает `app.actions`.
- **Защита работает всегда.** Она — задача планировщика (`protect` раз в секунду), а не часть экрана.
  Модальные окна — это просто слой отрисовки, цикл продолжает крутиться.
- **Каждое действие — через `core/actions`.** Кнопки, чат, клавиши TUI и защита вызывают одни и те же
  функции, поэтому и сообщения в журнале одинаковые.
- **Каждый вызов компонента стоит тик (0,05 с).** Поэтому опрос разбит на группы с разной частотой
  (см. `App.POLL`), а интерфейс не дёргает железо.
- **`state.version`** растёт при каждом изменении (`state:touch()`); интерфейс перерисовывает кадр,
  только если версия изменилась (или пора обновить часы).

---

## 2. Файлы: репозиторий и установка в игре

### Репозиторий

```
src/                    исходники v2 (ставятся в /home/reactorcontrol/)
  main.lua              точка входа
  update.lua            ручное обновление: скачать и запустить свежий установщик
  core/ hw/ logic/ net/ commands/ ui/   модули (описаны ниже)
  images/dark.pic light.pic             фоны (формат OCIF)
installer/
  install_v2.lua        установщик/обновлятор v2 (графический)
  updater.lua           мост v1 -> v2 (его скачивает и запускает старая программа)
  installer.lua         старая команда установки v1, теперь просто ставит v2
lib/                    библиотеки MineOS legacy (ставятся в /lib)
version_v2.txt          последняя версия v2 (по ней v2 видит обновление)
changelog_v2.lua        история изменений v2 (окно обновления и вкладка «Изменения»)
about_v2.txt            текст вкладки «Общая информация»
versions.txt            версия для СТАРОЙ v1 (2.0.0 => v1 предложит обновиться и придёт в updater.lua)
changelog.lua           история v1 (показывается в «Изменениях» после v2)
supporters.txt          список благодарностей (для v1)
CHANGELOG.md README.md  для GitHub
docs/                   этот файл, план рефакторинга, гайд для форума и скриншоты
tests/                  юнит-тесты на чистом Lua 5.3
tools/emu/              headless-эмулятор OpenComputers
tools/probe/            зонд для изучения реального API реактора в игре
```

### В игре после установки

| Путь | Что это |
|---|---|
| `/home/reactorcontrol/` | программа (копия `src/`) |
| `/home/reactorcontrol/main.lua` | запуск |
| `/home/reactorcontrol/update.lua` | ручное обновление |
| `/home/reactorcontrol/data/config.cfg` | настройки (serialize-таблица) |
| `/home/reactorcontrol/data/config.cfg.broken` | сюда переименовывается битый конфиг |
| `/home/reactorcontrol/data/reactor.log` и `.log.1` | журнал с ротацией (64 КБ) |
| `/home/data/config.lua` | конфиг v1 — читается один раз для переноса настроек |
| `/home/.shrc` | автозапуск: строка `/home/reactorcontrol/main.lua` |
| `/home/.rc_once.lua` | одноразовый запуск после перезагрузки из установщика (сам себя удаляет) |
| `/lib/doubleBuffering.lua`, `image.lua`, `color.lua`, `advancedLua.lua`, `/lib/FormatModules/OCIF.lua` | библиотеки интерфейса |
| `/home/main.lua` и т.п. | файлы v1 — установщик их НЕ удаляет |

---

## 3. Запуск и главный цикл

### `src/main.lua`

1. Находит свою папку (`debug.getinfo(1).source`, `@`/`=`) и ставит `package.path = ROOT/?.lua;…`.
2. **Выгружает свои модули** из `package.loaded` (префиксы `core.`, `hw.`, `logic.`, `net.`, `commands.`, `ui.`):
   OpenOS держит `require`-модули до перезагрузки, без этого после обновления работал бы старый код.
3. Аргументы:
   - без аргументов — графический интерфейс (`doubleBuffering`, разрешение 160×50);
   - `--nogui` — текстовый режим (`ui/textui.lua`): слева журнал, справа реакторы; клавиши
     `s` запустить все, `x` остановить все, `1–6` переключить реактор, `m` обновить МЭ, `q` выход;
   - `--plain` — без экрана вообще, журнал просто печатается строками.
4. `App.new{component, computer, event, configPath, legacyConfigPath, logPath}` → `ui:attach()` →
   `app:init()` → если `cfg.firstStart` — открыть окно настроек → `app:run()`.
5. После выхода из цикла смотрит `app.exitReason`:
   `"restart"` → `computer.shutdown(true)`; `"update"` → `update.lua --auto`; `"exit"` → просто выход.

### Последовательность `App:init()`

1. Шапка журнала (версия, автор, соавтор), предупреждения конфига; если конфиг перенесён из v1 — сохранить.
2. `scan()` — найти реакторы/МЭ/Flux/чат-бокс, сразу опросить новые реакторы (статика, hasWork, статистика, стержни, буфер).
3. Политика старта `cfg.onStart`: `"stop"` (по умолчанию, как в v1) — выключить все работающие реакторы;
   `"adopt"` — подхватить работающие (`desired = true`).
4. `actions:syncUsers()` — выдать `computer.addUser` игрокам из белого списка.
5. Подключить чат, поприветствовать, расписать задачи (`schedule()`).

### `App:step()` — один проход цикла

```
wait = min(scheduler:timeUntilNext(), ui.waitHint())
ev = event.pull(wait)
  component_added/removed -> scheduler:runSoon("scan", 0.5)
  interrupted (Ctrl+Alt+C) -> выход
  handlers[ev.name](...)   -- touch/key_down/scroll от интерфейса, chat_message от чата
scheduler:run()            -- все задачи, у которых подошло время
onFrame()                  -- отрисовка (сама решает, нужно ли рисовать)
```

`App:run()` крутит `step()` в `xpcall`: ошибка одного шага пишется в журнал и **не роняет** программу.
При выходе `shutdown()` останавливает все реакторы и сбрасывает журнал на диск.

### Расписание опроса (`App.POLL`, секунды: `{интервал, сдвиг}`)

| Задача | Интервал | Что делает |
|---|---|---|
| `coolant` | 1 | буфер жидкостных реакторов, которые работают / остановлены защитой / заблокированы |
| `protect` | 1 | `protection.evaluate` → команды → `actions:apply` |
| `running` | 5 | `hasWork` — заметить ручной запуск/остановку через интерфейс реактора |
| `stats` | 10 | температура, генерация |
| `rods` | 30 | стержни (топливо, время распада) |
| `static` | 60 | тип (жидк./возд.), объём буфера, номинальный расход, уровень |
| `me` | 60 | хладагент в МЭ (с учётом кулдауна; при нехватке — каждые 20 с) |
| `flux` | 5 | вход/выход Flux (direct, бесплатно) |
| `scan` | 30 | пересканировать компоненты (на случай пропущенных событий) |
| `logflush` | 10 | записать журнал на диск |
| `net` | 0,25 | продвинуть HTTP-запросы на шаг |
| `about` / `changelog` | 1800 | скачать about_v2.txt / changelog.lua (v1) |
| `updates` | 3600 | changelog_v2.lua, потом version_v2.txt |

Сдвиги нужны, чтобы группы не попадали в один тик.

---

## 4. core — ядро

### `core/app.lua` — приложение

Поля объекта `app`, которыми пользуются все остальные:

| Поле | Что |
|---|---|
| `app.cfg` | настройки (таблица по `config.SCHEMA`) |
| `app.cfgInfo` | `{source = "file"/"legacy"/"default", warnings = {...}}` |
| `app.state` | состояние (см. `core/state.lua`) |
| `app.log` | журнал |
| `app.actions` | действия |
| `app.scheduler` | планировщик |
| `app.http` | неблокирующий HTTP |
| `app.proxies` | `{reactors = {slot -> proxy}, me, flux, chat}` |
| `app.remote` | данные с GitHub: `about` (строки), `changelog` (v1), `changelogV2`, `latest` (версия), `notes` |
| `app.clock()` | время, по умолчанию `computer.uptime` |
| `app.saveConfig()` | сохранить `app.cfg` (ошибку пишет в журнал) |
| `app.ui` / `app.tui` | интерфейс, если есть |
| `app.onFrame`, `app.waitHint` | ставит интерфейс в `attach()` |
| `app.exitReason` | `"exit"` / `"restart"` / `"update"` |
| `App.VERSION`, `App.VERSION_SHORT`, `App.UPDATE_BRANCH` | версия и ветка обновлений |

Функции:

| Функция | Что делает |
|---|---|
| `App.new(deps)` | собрать приложение; `deps`: `component, computer, event, clock?, configPath, legacyConfigPath, logPath` |
| `app:on(eventName, fn)` | обработчик события (один на имя; `fn` получает аргументы `event.pull`) |
| `app:init()` | см. выше |
| `app:schedule()` | расписать все задачи опроса |
| `app:scan()` | обнаружение компонентов + первичный опрос новых реакторов; сохраняет конфиг, если номера изменились |
| `app:forEachOnline(fn)` | `fn(r, proxy)` для каждого реактора на связи |
| `app:protect()` | один шаг защиты |
| `app:pollMe()` | опрос МЭ с учётом кулдауна |
| `app:fetchAbout()`, `app:fetchChangelog()`, `app:checkUpdates()` | запросы на GitHub |
| `app:step(maxWait?)`, `app:run()`, `app:shutdown()` | цикл |
| `app:requestExit()`, `app:requestRestart()`, `app:requestUpdate()` | выйти из цикла с причиной |

### `core/actions.lua` — все действия пользователя и защиты

`app.actions = Actions.new(app)`. Все функции пишут понятные сообщения в журнал.

| Функция | Что делает |
|---|---|
| `start(slot?, who?)` | запустить реактор `slot` или все (`nil`). Ставит `desired = true`, снимает `unstable`/`buffer_low`. Пропускает реакторы без связи, заблокированные и с аварией МЭ. **Счётчик ручных запусков при пустом буфере**: если у реактора `buffer_low`, `manualTries++`; при превышении `cfg.maxManualStarts` — `faults.locked` и красная ошибка «запустите вручную через интерфейс реактора» |
| `stop(slot?, who?)` | остановить; `desired = false`; у ждущего автозапуска — «автозапуск отменён» |
| `toggle(slot)` | работает → `stop`, иначе → `start` (кнопка на виджете, клавиши 1–6) |
| `apply(commands)` | выполнить команды защиты `{op = "stop"/"start", slot, reason}` |
| `observeRunning(r, observed)` | сравнить `hasWork` с тем, что думает программа: запуск руками — ставит `startedAt` (льготный период), снимает `locked`/`buffer_low`; остановка руками — `desired = false`, распознаёт «кончилось топливо» |
| `forget(slot, renumber)` | забыть реактор без связи; `renumber = true` — перенумеровать остальные 1..n (в state, proxies, `cfg.reactorSlots`) |
| `refreshMe()` | опросить МЭ прямо сейчас (кнопка «Пр.Обновить МЭ», клавиша `m`) |
| `setThreshold(v)` | порог хладагента + сохранение |
| `addUser(nick)`, `removeUser(nick)` | белый список → `ok, err` |
| `syncUsers()` | привести `computer.addUser/removeUser` к `cfg.users` (`cfg.usersApplied` — кому уже выдано) |

Внутри: `doStart(r)` — `activate`, `running = true`, `halted = false`, `startedAt = now`;
`doStop(r)` — `deactivate`, `running = false`, `stoppedAt = now`. `Actions.kindName(r)` — «жидкостный»/«воздушный».

### `core/state.lua` — состояние

`State.new(clock)`, `State.MAX_REACTORS = 6`.

```lua
state.version          -- растёт в touch()
state.startedAt        -- время старта программы
state.reactors[slot]   -- записи реакторов (slot = 1..6, могут быть дыры)
state.me   = {present, amount, lastOk, cooldownUntil, error}
state.flux = {present, input, output, buffer}
state.chat = {present}
```

Запись реактора (`state:newReactor(slot, address)`):

| Поле | Что |
|---|---|
| `slot`, `address`, `online` | номер, адрес компонента, на связи ли |
| `kind` | `"fluid"` / `"air"` |
| `running` | работает (по последним данным) |
| `desired` | пользователь хочет, чтобы работал |
| `halted` | остановлен защитой и ждёт автозапуска |
| `faults` | `код -> {since, text, hinted?}`; коды см. `protection.TEXT` |
| `temp`, `maxTemp`, `rf`, `level` | статистика |
| `coolant`, `coolantMax`, `consumeNominal` | буфер и номинальный расход |
| `rods` | `{min, max, sum, count, maxFuel}` |
| `drain`, `burn` | счётчики `logic/rate` |
| `restarts` | времена автозапусков (для ограничения) |
| `startedAt`, `stoppedAt`, `manualTries`, `needStatic`, `lastSeen` | служебное |

Функции: `touch()`, `newReactor`, `removeReactor(slot)`, `list()` (по номерам), `count()`,
`totalRf()`, `totalDrain()`, `anyRunning()`, `uptime()`.

### `core/config.lua` — настройки

- `config.load(path, legacyPath) -> cfg, info`. Порядок: файл → конфиг v1 (`fromLegacy`) → значения по умолчанию.
  Битый файл переименовывается в `.broken`, причина — в `info.warnings`.
- `config.save(cfg, path)` — атомарно (временный файл + rename), с комментарием в начале.
- `config.normalize(raw) -> cfg, warnings` — каждое поле проверяется своей `check`; неверное заменяется значением по умолчанию.
- `config.fromLegacy(text)` — v1: `porog → threshold`, `users`, `usersold → usersApplied`, `theme` (bool → dark/light), `updateCheck`, `debugLog`, `isFirstStart → firstStart`.
- `config.defaults()`.

Все параметры (`config.SCHEMA`). В интерфейсе меняются только порог, тема, проверка обновлений,
отладка, автозапуск и белый список — остальное правится в файле `data/config.cfg`.

| Параметр | По умолч. | Смысл |
|---|---|---|
| `threshold` | 50000 | порог хладагента в МЭ, mB; ниже — жидкостные стоп |
| `users` / `usersApplied` | {} | белый список / кому выдан `addUser` |
| `theme` | dark | `dark`/`light` |
| `updateCheck` | true | проверять обновления |
| `debugLog` | false | писать в файл уровень debug |
| `firstStart` | true | показать настройки при первом запуске |
| `metric` | auto | единицы: `auto`, `""`, `k`, `m`, `g` |
| `reactorSlots` | {} | адрес компонента → номер 1..6 (постоянные номера) |
| `autoRestart` | true | запускать обратно, когда авария прошла |
| `bufferStopSec` | 5 | мягкий порог буфера, секунд работы |
| `bufferHardStopSec` | 2 | жёсткий порог (действует и в льготный период) |
| `startGraceSec` | 4 | после запуска до первого долива — только жёсткий порог |
| `maxManualStarts` | 3 | ручных запусков при пустом буфере до блокировки |
| `bufferAutoRestart` | false | после аварии буфера запускать самому |
| `bufferRestartSec` | 4 | …если буфера хватит хотя бы на N с |
| `bufferRetrySec` | 30 | …и не раньше чем через N с |
| `bufferResumePct` | 0.8 | буфер заполнен на долю — блокировка снимается |
| `bufferStopPct` | 0.5 | запасной порог в долях, если расход неизвестен |
| `drainFactor` | 100 | пока расход не замерен: номинал × N |
| `coolantName` | low_temperature_refrigerant | имя жидкости в МЭ |
| `meLostSec` | 180 | нет данных МЭ дольше N с → авария `me_lost` |
| `onStart` | stop | при старте программы: `stop` / `adopt` |
| `maxAutoRestarts` | 3 | автозапусков за окно, потом `unstable` |
| `autoRestartWindowSec` | 600 | окно для счёта автозапусков |

> Тест `test_config` проверяет, что каждое `cfg.xxx`, встречающееся в коде, есть в `SCHEMA`.
> Новый параметр без записи в схеме тест не пропустит.

### `core/log.lua` — журнал

`Log.new{path, clock, keep = 200, maxFileSize = 64K, fileLevel = "info", flushInterval}`.

- `log:write(level, text, opts)`; уровни `debug/info/warn/error`; `opts.color` — `"ok"`, `"title"` или цвет;
  `opts.noStack` — не склеивать повторы.
- Сокращения: `debug/info/warn/error(text)`, `ok(text)` (зелёный), `title(text)` (голубой, без склейки).
- **Склейка повторов:** одинаковое сообщение подряд увеличивает `entry.count` (на экране «×3»).
- `log.entries` — кольцо последних `keep` записей `{time, level, text, color, count}`; `log.version` растёт при записи.
- `log:onEntry(fn)` — подписка (так `--plain` печатает строки).
- `log:setFileLevel(level)`, `log:flush()` (дописать в файл, при превышении размера → `.log.1`), `log:tick()`.

### `core/scheduler.lua` — планировщик

`Scheduler.new(clock, onError)`.

| Функция | Что |
|---|---|
| `every(name, interval, fn, offset?)` | периодическая задача; `fn(now)` |
| `after(name, delay, fn)` | одноразовая |
| `runSoon(name, delay)` | перенести ближайший запуск задачи на `now + delay` (если раньше) |
| `cancel(name)`, `has(name)` | |
| `timeUntilNext()` | сколько ждать до ближайшей задачи (для `event.pull`) |
| `run()` | выполнить все созревшие (`pcall`, ошибка → `onError(task, err)`); без накопления дрейфа |

### `core/serialize.lua`

`serialize(value, pretty?)` и `unserialize(text) -> value | nil, err`. Разбор выполняется в пустом
окружении (доступно только `math.huge`) — данные с GitHub и конфиг не могут исполнить код.

### `core/fsutil.lua`

`read(path)`, `exists`, `makeDirectory`, `dirname`, `remove`, `rename`, `size`,
`writeAtomic(path, data)` (через `path.tmp` + rename), `append(path, data)`.

---

## 5. hw — работа с железом

Модули `hw/*` — тонкая прослойка: вызвать метод, разобрать ответ, записать в запись состояния.
Решений не принимают.

### `hw/reactor.lua`

| Функция | Что |
|---|---|
| `TYPE_PREFIX = "htc_reactors"` | по нему discovery узнаёт реакторы |
| `call(proxy, method, ...) -> ok, result...` | безопасный вызов: метода нет → `false, "нет метода X"`; ошибка → `false, err` |
| `kv(flat)` | плоская запись `{"item", name, "type", "fuelrod", ...}` → `{item = name, type = ...}` |
| `rodsSummary(rods)` | стержни (обход **через `pairs`** — слоты с дырами) → `{min, max, sum, count, maxFuel}` |
| `pollStatic(r, p)` | `isActiveCooling` → `kind`, `getMaxFluidCoolant` → `coolantMax`, `getFluidCoolantConsume` → `consumeNominal`, `getMaxTemperature`, `getReactorLevel` |
| `pollRunning(p) -> bool/nil` | `hasWork` |
| `pollCoolant(r, p, now)` | `getFluidCoolant` → `r.coolant`, кладёт отсчёт в `r.drain` |
| `pollStats(r, p)` | `getTemperature`, `getEnergyGeneration` |
| `pollRods(r, p, now)` | `getAllFuelRodsStatus` → `r.rods`, отсчёт в `r.burn` |
| `activate(p)`, `deactivate(p)` | |

### `hw/me.lua`

- `TYPES = {"me_controller", "me_interface"}`, `MIN_INTERVAL = 16`.
- `read(proxy, me, now, coolantName) -> "ok" | "cooldown" | "error"`.
  Вызывает `getFluidsInNetwork`, суммирует `amount` у жидкостей с `name == coolantName`.
  На `false, "cooldown", "14s"` ставит `me.cooldownUntil` — **это не авария**.
  При `"ok"` обновляет `me.amount`, `me.lastOk`.

### `hw/flux.lua`

`read(proxy, flux) -> ok`. Вызывает `getEnergyInfo` (direct, бесплатно) и заполняет `flux.input/output/buffer`
(`energyInput`, `energyOutput`, `totalBuffer`).

### `hw/discovery.lua`

`scan(component, state, cfg, log, proxies) -> changed`.

- Реакторы: все компоненты с типом на `htc_reactors`. Номер берётся из `cfg.reactorSlots[address]`.
  Новый адрес получает первый свободный номер, а если свободных нет — номер пропавшего реактора.
  Больше 6 — лишние игнорируются (одно предупреждение).
- Реактор из конфига, которого нет при старте, создаётся записью **без связи** (`online = false`, авария `offline`)
  + подсказка в журнале — чтобы на экране было видно, что он пропал, и была кнопка «Забыть».
- Реактор пропал во время работы → `online = false`; вернулся → снова на связи и `needStatic = true`.
- МЭ (`me_controller`/`me_interface`), Flux (`flux_controller`), чат-бокс (`chat_box`) — первый найденный.

---

## 6. logic — защита и замеры

### `logic/protection.lua` — правила защиты

Чистые функции, всё покрыто `tests/test_protection.lua`. Ничего не вызывает — только читает
`state`/`cfg` и возвращает решения.

Коды аварий (`protection.TEXT`): `offline` (нет связи), `locked` (заблокирован), `unstable`
(слишком много автозапусков), `me_lost` (нет данных МЭ), `me_low` (мало хладагента в МЭ),
`buffer_low` (кончается буфер). `firstFault(r)` возвращает самую важную в этом порядке.

| Функция | Что |
|---|---|
| `hasFaults(r)` | есть ли хоть одна авария |
| `firstFault(r) -> code, text` | главная авария для показа |
| `drainRate(r, cfg)` | реальный расход mB/s: замер `r.drain:rate()`, иначе `consumeNominal × drainFactor` |
| `bufferSeconds(r, cfg)` | на сколько секунд хватит буфера (`coolant / drainRate`) |
| `evaluate(state, cfg, now) -> commands, events` | один шаг защиты |

Что делает `evaluate` для каждого реактора на связи:

1. **МЭ (только жидкостные):** `me_lost`, если МЭ нет или данных не было дольше `meLostSec`;
   `me_low`, если `amount <= threshold`. Воздушные эти аварии не получают никогда.
2. **Буфер:** у работающего жидкостного считаются секунды буфера. Порог — `bufferHardStopSec` в первые
   `startGraceSec` после запуска (буфер ещё не долился), иначе `bufferStopSec`. Если расход неизвестен совсем —
   доля `bufferStopPct`. Ниже порога → `buffer_low`.
3. **Блокировка** снимается, когда буфер заполнен на `bufferResumePct` (или реактор запустили через его
   интерфейс — это в `actions:observeRunning`).
4. Минута стабильной работы обнуляет `manualTries`.
5. **`buffer_low` снимается только ручным запуском** (один раз пишется подсказка «хладагент не доходит из МЭ…»).
   Если включён `bufferAutoRestart` — снимается сама через `bufferRetrySec`, когда буфера ≥ `bufferRestartSec` и МЭ в порядке.
6. **Команды:** есть авария и реактор работает → `stop` (если `desired` — помечается `halted`).
   Аварий нет, реактор `halted` и `desired`, не работает, `autoRestart` включён → `start`,
   но не больше `maxAutoRestarts` за `autoRestartWindowSec`, иначе авария `unstable`.

`events` — `{level, text, color?, slot}` — App пишет их в журнал.

### `logic/rate.lua` — замер расхода и выгорания

**`rate.drain(size = 15)`** — реальный расход буфера.
`add(t, value, running)`: запоминает падения буфера между замерами (рост = долив, пропускается).
`rate()` — медиана положительных скоростей, mB/s; `nil`, пока данных мало. `reset()`.

**`rate.burn(window = 600)`** — скорость выгорания топлива.
`add(t, sample, running, stoppedAt)`: `sample` — сумма топлива по стержням; интервалы, в которые реактор
останавливался, не учитываются; при перезаправке или смене числа стержней история сбрасывается.
`rate()` — единиц/с. `remaining(now, running, stoppedAt) -> firstSec, lastSec` — время до опустошения
самого пустого и самого полного стержня; у остановленного реактора время «замирает» на момент `stoppedAt`.

---

## 7. net — интернет и GitHub

### `net/http.lua` — неблокирующий HTTP

`Http.new(component, clock)`. `internet.request` + `finishConnect` + `read` порциями — за один `step()`
делается немного работы, цикл не блокируется.

| Функция | Что |
|---|---|
| `available()` | есть ли интернет-карта |
| `get(url, cb, timeout = 20)` | поставить запрос в очередь; `cb(ok, dataOrError)` |
| `busy()` | есть ли запросы |
| `step()` | продвинуть текущий запрос (вызывается задачей `net` раз в 0,25 с) |

Ограничение ответа — 128 КБ, HTTP-код ≠ 200 → ошибка.

### `net/remote.lua` — разбор данных с GitHub

| Функция | Что |
|---|---|
| `REPO`, `MAIN` | `https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/`, `"main"` |
| `parseChangelog(text) -> list/nil` | пропускает комментарии `--` в начале, убирает `return`, `unserialize`, проверяет структуру `{ {version=, changes={...}}, ... }` |
| `parseAbout(text) -> lines` | строки about_v2.txt, кроме начинающихся с `#` |
| `notesBetween(list, cur, latest)` | записи changelog новее `cur` до `latest` включительно (для окна обновления) |
| `isNewer(remote, cur)` | сравнение версий `x.y.z`; версия с суффиксом (`2.1.0-dev`) считается старше релиза |

---

## 8. commands — чат-команды

`commands/chat.lua` (чат-бокс Computronics, событие `chat_message`).

- `attach(app)` — подписка на событие, `greet(app)` — имя бота `M.NAME` и приветствие.
- `handle(app, nick, message) -> handled`: убирает цветовые коды `§x`, ищет команду, проверяет белый
  список (`cfg.users`), выполняет в `pcall`.
- Команды: `@help`, `@status`, `@start [n]`, `@stop [n]`, `@setporog <mB>`, `@useradd <ник>`,
  `@userdel <ник>`, `@forget <n> [renum]`, `@changelog [версия]`, `@info`, `@restart`, `@exit`.
- `withLog(app, fn)` — ответы о запуске/остановке берутся **из журнала** (новые записи после `fn`),
  чтобы в чате было то же, что на экране. Не больше `MAX_SAY = 12` строк — каждая строка стоит тик.

---

## 9. ui — интерфейс

### Протокол экрана

Экран (главный или модальное окно) — это модуль с функциями:

```lua
M.open(ui)                 -- (необязательно) при открытии
M.draw(ui)                 -- нарисовать кадр в буфер и зарегистрировать зоны нажатий через ui:hit / ui:button
M.key(ui, char, code)      -- (необязательно) клавиатура
M.scroll(ui, x, y, dir)    -- (необязательно) колесо
M.wakeIn(ui) -> seconds    -- (необязательно) когда перерисовать (мигающий курсор и т.п.)
```

Зоны нажатий пересоздаются **каждый кадр**: что нарисовано — то и нажимается.

### `ui/ui.lua` — кадры, нажатия, модальные окна

`UI.new(app, buffer, {imagesDir})`.

| Функция | Что |
|---|---|
| `attach()` | подписать `touch`/`key_down`/`scroll`, поставить `app.onFrame` и `app.waitHint`, сохранить `app.ui` |
| `frame(force?)` | нарисовать кадр, если изменилась `state.version`/`log.version`/`cfg` или пора обновить часы (`CLOCK_INTERVAL = 1`), не чаще `MIN_FRAME = 0.1`. Один раз на каждую новую версию сам открывает окно обновления |
| `theme()` | текущая тема (`ui/theme`) |
| `background()` | картинка фона темы (кэш) |
| `hit(x1, y1, x2, y2, fn, id)` | зона нажатия; позже добавленные — сверху |
| `button(id, x, y, len, text, color, textColor, onClick)` | кнопка + зона + анимация нажатия |
| `isPressed(id)` | кнопка ещё «нажата» (`PRESS_TIME = 0.2`) |
| `openModal(screen)`, `closeModal()` | модальное окно поверх главного экрана |
| `invalidate()` | перерисовать на следующем кадре |
| `touch / key / scroll` | обработчики событий |
| `timeUntilNext()` | для `waitHint` |

Анимация кнопки: при нажатии кнопка сначала рисуется нажатой (`frame(true)`), потом выполняется действие —
иначе долгое действие (вызовы реакторов) «съедало» анимацию.

### `ui/gfx.lua` — примитивы рисования

Обёртки над `doubleBuffering`, внешний вид как в v1.1.3. `G.init(buffer)` вызывает UI.

| Функция | Что |
|---|---|
| `text(x, y, color, s)` | текст; **широкие символы** (🔧 ⓘ ⚠) занимают 2 колонки — следующая ячейка ставится пустой |
| `fit(s, width)` | обрезать с «…» |
| `center(x, width, color, s, y)` | по центру |
| `rect(x, y, w, h, color)`, `dim(alpha)` | прямоугольник, затемнение экрана под модальным окном |
| `box(x, y, w, h, color)` | рамка со скруглёнными брайль-углами |
| `hline(x, y, w, ch, color)` | линия из брайль-символа |
| `button(x, y, len, text, color, textColor, pressed) -> x1, y1, x2, y2` | кнопка v1 |
| `number(cx, y, value, color, suffix, suffixColor)` | крупные брайль-цифры по центру |
| `icon(x, y, img, color)` | брайль-картинка |
| `vbar(x, y, h, value, max, cBottom, cTop, inactive)` | вертикальная шкала с градиентом (`lerp`) |
| `switch(...)`, `field(...)` | переключатель и поле ввода (окно настроек) |

### `ui/braille.lua` и `ui/sprites.lua`

Брайль-символ = ячейка 2×4 точки, две краски: точки — цвет текста, остальное — фон.

- `braille.image(rows)` — картинка из ASCII-арта: строки одинаковой длины, `'#'` — точка, `'.'` или пробел — фон.
  Ширина кратна 2, высота кратна 4.
- `braille.set(list)` — набор отдельных ячеек; `braille.cell(rows)` — одна ячейка.
- `braille.draw(buffer, x, y, img, fg)`, `braille.line(...)`, `braille.char(mask)` (кэш 256 символов),
  `braille.fromDots(d)` — старый формат v1 (используется только в тестах).
- `sprites.lua` — все картинки интерфейса в виде ASCII-арта: `digit0..9`, `console`, `iconFluid/Plus/Minus/Bolt/Time`,
  `divider`, `button`, `buttonPushed`, `corner`, `field`, `vbar`. Изначально сгенерированы из таблиц v1,
  `tests/test_braille.lua` сверяет их с оригиналом — при правке спрайта поправьте и тест.

### `ui/theme.lua`

`theme.dark`, `theme.light`, `theme.get(name)`. Ключи: `name`, `image` (фон .pic), `bg`, `bg2`, `bg3`, `bg4`,
`text`, `textBtn`, `btn`, `btnPressed`, `version`, `info`, `ok`, `warn`, `error`, `title`.
Новый цвет — добавлять в **обе** темы.

### `ui/format.lua`

`si(value, metric) -> число, приставка` (с учётом `cfg.metric`), `compact(value)` (290k, 1.2M),
`hms(seconds)`, `percent(v, max)`, `METRIC_ORDER`, `METRIC_LABEL`.

### Экраны (`ui/screens/`)

| Экран | Что |
|---|---|
| `main.lua` | главный экран 160×50. Виджеты 34×16 в позициях `M.WIDGETS` (6 шт.: 3×2). Виджет: Нагрев, Ген, Тип, Статус/Авария, Буфер % (сек), Расход, Топливо мин–макс %, Распад первого/последнего стержня, шкала буфера слева, кнопка (Отключить / Отменить / Включить / Заблокирован / Забыть). Справа: консоль (журнал), жидкость в МЭ, порог ± (шаг зависит от величины), Flux, генерация, время. Снизу: статус комплекса и кнопки 🔧 ⓘ, запуск/стоп, обновить МЭ, метрика, рестарт, выход |
| `settings.lua` | черновик настроек (`open` копирует cfg), порог, переключатели (тема, обновления, отладка, автозапуск), белый список (Del/ADD), «Сохранить и выйти» |
| `info.lua` | вкладки: «Общая информация» (`app.remote.about` или встроенный текст `INFO`), «Изменения в версиях» (v2 + v1, заголовки `#`), лицензия MIT; прокрутка |
| `update.lua` | «Доступно обновление»: `app.remote.notes`, кнопки «Обновить» (`app:requestUpdate()`) / «Позже» |
| `forget.lua` | подтверждение «Забыть» / «Забыть и перенумеровать» / «Отмена» |

### `ui/textui.lua` — текстовый режим (`--nogui`)

`TUI.new(app, gpu)`, `frame(force)`, `drawLog`, `drawStatus`, `timeUntilNext`. Рисует прямо через GPU,
с кэшем строк (`row`) — перерисовываются только изменившиеся.

---

## 10. Внешние библиотеки

Из MineOS legacy (как в v1), лежат в `lib/`, ставятся в `/lib`. Код программы использует только две:

- **`doubleBuffering`** — экранный буфер в памяти, отрисовка только изменений. Используются
  `setResolution`, `getResolution`, `clear`, `drawRectangle`, `drawText`, `set`, `get`, `drawImage`, `drawChanges`.
  `drawChanges` сравнивает весь буфер, поэтому кадры рисуются только при изменениях.
- **`image`** — загрузка `.pic` (формат OCIF, модуль `/lib/FormatModules/OCIF.lua`). Фоны тем.
- `color`, `advancedLua` — зависимости этих двух.

`/lib/event.lua` установщик не трогает (в v1 был патч, в v2 не нужен).

---

## 11. Факты о реальном железе (HiTech, ME, Flux)

Получены зондом `tools/probe` на сервере McSkill HiTech 1.12.2:

- Тип компонента реактора: `htc_reactors_nuclear_reactor`.
- Методы: `activate`, `deactivate`, `hasWork`, `isActiveCooling`, `setActiveCooling`, `getTemperature`,
  `getMaxTemperature`, `getEnergyGeneration`, `getFluidCoolant`, `getMaxFluidCoolant`, `getFluidCoolantConsume`,
  `getAllFuelRodsStatus`, `getSelectStatusRod(slot)`, `getReactorComponents`, `getReactorComponent(slot)`,
  `getCoolantItem(slot)`, `getReactorLevel`, `isFuelFilterActive`.
- `getTemperature` почти бесполезна (9998/9999, у калифорниевого 0/0) — показывается, но не используется защитой.
- Буфер жидкостного реактора (MOX, ур. 6): 1 296 000 mB максимум. Реальный расход ≈ **номинал × 100**
  (`getFluidCoolantConsume` занижен в 100 раз) — отсюда `drainFactor = 100`.
- Буфер **доливается до полного раз в 3 секунды и только у работающего реактора** (91% → 82% → 73% → 91%).
  Остановленный реактор буфер не доливает — поэтому авария буфера не снимается сама.
- `getAllFuelRodsStatus` — разреженная таблица по слотам (1–9, 12, 13, 16–24): обходить **через `pairs`**.
  Запись плоская: `{"item", name, "type", "fuelrod", "fuel", N, "maxFuel", 10000}` → `reactor.kv`.
- Выгорание ~2,95 ед./с на стержень, с нанитами быстрее — поэтому время распада считается по замеру.
- МЭ: `getItemsInNetwork` и `getFluidsInNetwork` делят **общий кулдаун ~15 с**, во время него возвращают
  `false, "cooldown", "14s"`. Хладагент: `name = "low_temperature_refrigerant"`.
- Flux: методы direct (без тика).
- Методы прокси компонента — **вызываемые таблицы, а не функции** (`type(p.activate) == "table"`).

---

## 12. Установщик, обновление, переход с v1

### `installer/install_v2.lua`

Графический установщик (100×32). Команда установки:

```
wget -fq https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/main/installer/install_v2.lua /home/rc_install.lua && /home/rc_install.lua
```

- Режимы: `install` (нет `/home/reactorcontrol/main.lua`), `update`, плюс отметка «найдена v1».
- Проверки: интернет-карта, GPU/монитор, память.
- Галочка автозапуска: правит `/home/.shrc` (убирает старые строки `main.lua`, `/home/main.lua`, добавляет `/home/reactorcontrol/main.lua`).
- Загрузка: список `FILES` (из `src/`) + `LIBS`, с повторами, атомарно. Если что-то не скачалось — установленная версия не трогается.
- Опции: `--yes` (без вопросов, без перезагрузки), `--auto` (без вопросов, отсчёт и перезагрузка — так вызывает обновление),
  `--branch=имя` (ставить из другой ветки, для тестов).
- «Перезагрузить и запустить»: если автозапуск выключен — одноразовый `/home/.rc_once.lua`.

> **Новый файл в `src/` обязательно добавить в `FILES`!** Тест `tests/test_installer.lua` сверяет
> список с содержимым `src/` и упадёт, если забыли.

### Обновление v2 → v2

1. Задача `updates` скачивает `changelog_v2.lua` и `version_v2.txt` из ветки `App.UPDATE_BRANCH`.
2. Если версия новее `App.VERSION` — запись в журнале и окно «Доступно обновление» (один раз на версию).
3. «Обновить» → `app:requestUpdate()` → цикл останавливается, реакторы выключаются →
   `main.lua` запускает `update.lua --auto` → скачивается свежий `install_v2.lua` → ставит → перезагрузка.

### Переход с v1

Старая v1 проверяет `versions.txt`. Там `2.0.0` → v1 показывает своё окно обновления и при согласии
скачивает и запускает `installer/updater.lua` → тот ставит v2 с `--auto`. Настройки v1
(`/home/data/config.lua`) переносятся при первом запуске v2 (`config.fromLegacy`). Файлы v1 остаются.
`installer/installer.lua` (старая команда установки v1) тоже просто ставит v2.

**`versions.txt` больше не трогать** — он нужен только чтобы v1 ушла на v2.

---

## 13. Файлы, которые правятся на GitHub без выпуска версии

В ветке `main`, программа подхватывает их сама:

| Файл | Когда подхватится | Формат |
|---|---|---|
| `about_v2.txt` | при запуске и раз в 30 мин | текст; строки с `#` — комментарии; пустая строка — отступ; длинные строки переносятся |
| `changelog_v2.lua` | при запуске и раз в час | Lua-таблица-данные (без кода!); новые версии **в конец**; строка `"# Заголовок"` — раздел |
| `version_v2.txt` | раз в час | одна строка `x.y.z` — меняется только при выпуске |

Пример записи changelog:

```lua
  {
    version = "2.1.0",
    changes = {
      "# Защита",
      "Пункт изменения",
      "# Интерфейс",
      "Ещё пункт",
    },
  },
```

---

## 14. Как выпустить новую версию

1. Изменения в `src/`; новые файлы — в `FILES` установщика.
2. `App.VERSION` (и `App.VERSION_SHORT`, если меняется x.y) в `src/core/app.lua`.
3. Запись в конец `changelog_v2.lua`, раздел в `CHANGELOG.md`.
4. Проверка: `lua5.3 tests/run.lua` и сценарии эмулятора (минимум `v2_smoke`, `v2_gui`, `install_v2`).
5. Для теста в игре можно поставить из ветки: `/home/rc_install.lua --branch=имя_ветки`.
6. Влить в `main` **код и `changelog_v2.lua` раньше**, а `version_v2.txt` — **последним**: как только
   в нём новая версия, все программы предложат обновиться и скачают то, что лежит в `main`.

Номера: `x.y.z` — исправления в `z`, новые функции в `y`.

---

## 15. Тесты, эмулятор, зонд

### Тесты

```bash
lua5.3 tests/run.lua            # все
lua5.3 tests/run.lua protection # только тесты, в имени которых есть "protection"
```

`T.eq`, `T.near`, `T.ok`, `T.no`, `T.test(name, fn)`; есть управляемые часы и фейковые прокси.
Файлы: `test_serialize`, `test_config`, `test_scheduler`, `test_rate`, `test_protection`, `test_hw`,
`test_braille`, `test_format`, `test_installer`, `test_remote`, `test_chat`.

### Эмулятор (`tools/emu/`, подробности в `tools/emu/README.md`)

Headless OpenComputers на Lua 5.3: виртуальное время (минута работы — за секунды), GPU 160×50 со шрифтом OC,
моки реактора (с реальной динамикой буфера и выгорания), МЭ (с общим кулдауном), Flux, чат-бокса, интернета.
Песочница ФС — `/tmp/rc_emu_root`.

```bash
cd tools/emu
lua5.3 emu.lua scenarios/v2_gui.lua
python3 -I render.py /tmp/rc_emu_out/<дамп>.txt out.png    # скриншот (нужен Pillow)
```

Сценарии v2: `v2_smoke` (защита без GUI), `v2_gui` (все экраны и кнопки), `v2_net` (GitHub, обновление, чат),
`v2_tui`, `v2_nogui_keys`, `v2_forget`, `v2_reload` (выгрузка модулей), `install_v2`, `migrate_v1`
(v1 → updater → v2), `guide_shots`/`guide_tui` (скриншоты для гайда). `legacy_*` — эталон и баги v1.

API сценария: `emu.at(t, fn)`, `emu.touch(x, y, nick)`, `emu.chat(nick, msg)`, `emu.key(char, code)`,
`emu.dump(path)`, `emu.screenText()`, `emu.addComponent/removeComponent`, `emu.endTime`, `emu.run`,
`emu.runVirtual`, `emu.install`. Состояние моков меняется напрямую: `reactor.state.coolant = 0`, `me.state.fluid = 0`.

### Зонд (`tools/probe/probe.lua`)

Запускается в игре, только читает (кроме `--toggle`). Печатает все методы и ответы реакторов, МЭ, Flux.
Опции: `--watch=N` (наблюдать N секунд — так замеряли долив и выгорание), `--reactor=N`, `--cooldown`
(проверить кулдаун МЭ), `--toggle=N`, `--all`. Использовать, если сервер обновил мод и что-то сломалось.

---

## 16. Рецепты: как добавить …

### …новую строку в виджет реактора

1. Данные: если нужен новый метод реактора — опросить в подходящей `poll*` в `hw/reactor.lua`,
   положить в поле записи `r` (и описать поле в `state:newReactor`).
2. Отрисовка: `drawWidget` в `ui/screens/main.lua`. Высота виджета 16 строк — места почти нет.
3. Тот же показатель стоит добавить в `ui/textui.lua` (`reactorLines`) и, если полезно, в `@status`.

### …новую настройку

1. Поле в `config.SCHEMA` (`default` и `check`).
2. Если её нужно менять в интерфейсе — строка в `ui/screens/settings.lua` (`toggleRow` для bool).
3. Сохранение — `app.saveConfig()`; черновик настроек сохраняет всё сам.

### …новую чат-команду

`commands["@имя"] = function(app, args, nick) ... end` в `commands/chat.lua` + строка в `HELP`.
Действия — только через `app.actions`; для ответа о запуске/остановке оборачивать в `withLog`.

### …новое правило защиты

1. Код аварии и текст в `protection.TEXT`, место в порядке `firstFault`.
2. Установка/снятие в `evaluate` через `setFault`/`clearFault` — тогда команда `stop` и автозапуск сработают сами.
3. Тест в `tests/test_protection.lua`.

### …новое окно

Модуль в `ui/screens/` с `draw(ui)` (+ `open/key/scroll` по желанию), открыть `ui:openModal(require("ui.screens.x"))`,
закрыть `ui:closeModal()`. **Добавить файл в `FILES` установщика.**

### …новую картинку (спрайт)

ASCII-арт в `ui/sprites.lua` через `img{...}` (ширина кратна 2, высота кратна 4), рисовать `G.icon(x, y, S.name, color)`.

### …новую задачу опроса

Строка в `App.POLL` и `s:every(...)` в `App:schedule()`. Помнить: каждый вызов компонента — тик.

---

## 17. Грабли (то, на что уже наступали)

- **Методы прокси — вызываемые таблицы.** Проверять `proxy.m == nil`, а не `type(proxy.m) ~= "function"`
  (из-за этого в игре было «нет метода activate»). Эмулятор моделирует это так же.
- **Кэш модулей OpenOS.** Без выгрузки в `main.lua` после обновления работает старый код до перезагрузки.
- **`shell.parse`:** значения только в виде `--key=value`; `--key 120` даёт `true` и позиционный аргумент.
- **Широкие символы** (🔧 ⓘ ⚠) на GPU занимают 2 колонки — только через `G.text`.
- **Кулдаун МЭ ~15 с** — не авария (баг v1 останавливал все реакторы).
- **Стержни по `pairs`**, не `ipairs` (баг v1: слоты с дырами).
- **Простаивающий реактор не доливает буфер** — не ждать заполнения у остановленного.
- **Пороги буфера:** 6 с оказалось слишком много (один пропущенный долив ~5,1 с) → 5 с мягкий, 2 с жёсткий, 4 с льготы.
- **`format.compact`** когда-то отрезал нули целых чисел (290k → 29k) — есть тест.
- **Таймер распада после остановки** продолжал убывать — теперь `remaining()` учитывает `stoppedAt`.
- **Комментарии в начале `changelog_v2.lua`** — `parseChangelog` их пропускает; но сам файл должен оставаться
  чистой таблицей без кода (разбирается в пустом окружении).
- **Новый файл без записи в `FILES`** — не попадёт в игру (ловит тест).
- **Отладочный журнал:** включить «Отладку» в настройках → в `data/reactor.log` пишется уровень debug
  (ответы GitHub, ошибки разбора и т.п.).
