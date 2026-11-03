# Reactor Control v2 — исходники

Устанавливается в игре в `/home/reactorcontrol/`, запуск: `/home/reactorcontrol/main.lua`.

```
main.lua            точка входа: пути модулей, сборка App, цикл
core/
  app.lua           расписание опроса, единый цикл событий, защита в каждом шаге
  actions.lua       все действия: запуск/остановка, команды защиты, порог, пользователи
  state.lua         единое состояние (логика пишет, интерфейс читает; version растёт при изменениях)
  config.lua        схема настроек, проверка, атомарное сохранение, перенос старого /home/data/config.lua
  log.lua           журнал: кольцо в памяти для консоли + файл с ротацией
  scheduler.lua     периодические задачи по computer.uptime
  serialize.lua     таблица <-> текст без исполнения кода
  fsutil.lua        файлы: атомарная запись через временный файл
logic/
  protection.lua    правила защиты (чистые функции, покрыты тестами)
  rate.lua          замер реального расхода буфера и скорости выгорания топлива
hw/
  reactor.lua       htc_reactors_nuclear_reactor: группы опроса, разбор плоских записей, стержни по pairs
  me.lua            ME: getFluidsInNetwork, общий кулдаун ~15 с — не авария
  flux.lua          Flux Networks (direct)
  discovery.lua     поиск компонентов, постоянные номера реакторов (адрес -> номер в конфиге)
```

ui/
  ui.lua            кадры, зоны нажатий, анимация без sleep, модальные окна как слой поверх экрана
  gfx.lua           примитивы v1.1.3: текст (с широкими символами), кнопка, рамка, брайль-цифры, полоса, переключатель, поле
  braille.lua       брайль: кэш 256 символов, картинки из ASCII-арта
  sprites.lua       все брайль-спрайты в виде ASCII-арта ('#' — точка)
  theme.lua         тёмная и светлая темы
  format.lua        числа и время
  screens/main.lua      главный экран
  screens/settings.lua  окно настроек
  screens/info.lua      окно информации
images/             фоны .pic для тем

Запуск без интерфейса (журнал в терминал): `main.lua --nogui`.

## Установка в игре (тест)

```
wget -f https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/claude/keen-volta-rnypyl/installer/install_v2.lua /home/install_v2.lua
install_v2
/home/reactorcontrol/main.lua
```
Старая версия и её настройки не трогаются, v2 переносит настройки сама.

## Проверка без игры

```bash
lua5.3 tests/run.lua                 # модульные тесты (из корня репозитория)
cd tools/emu && lua5.3 emu.lua scenarios/v2_smoke.lua   # вся программа в эмуляторе
```
