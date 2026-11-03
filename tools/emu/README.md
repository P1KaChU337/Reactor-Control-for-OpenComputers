# Headless-эмулятор OpenComputers

Нужен, чтобы запускать Reactor Control без Minecraft: прогонять сценарии, ловить ошибки
и снимать скриншоты экрана. Это не полный эмулятор OC, а набор заглушек под то, что
использует программа.

Что есть:
- виртуальное время: `os.sleep` и `event.pull` двигают часы, а не ждут по-настоящему,
  так что минута работы программы прогоняется за пару секунд;
- GPU 160×50 с подсчётом вызовов (`gpuCalls`);
- компоненты-моки в `mocks.lua`: `htc_reactors`, `me_controller`/`me_interface`,
  `flux_controller`, `chat_box`, с подсчётом вызовов (`componentCalls`);
- песочница ФС: все абсолютные пути уходят в `$EMU_ROOT` (по умолчанию `/tmp/rc_emu_root`);
- `wget` через `os.execute`/`shell.execute` отдаёт данные из `emu.http[url]`;
- `thread` на корутинах.

## Запуск

```bash
sudo apt-get install lua5.3
cd tools/emu
rm -rf /tmp/rc_emu_root
lua5.3 emu.lua scenarios/legacy_smoke.lua
python3 render.py /tmp/rc_emu_out/legacy_02_running.txt out.png   # нужен Pillow
```

`render.py` также рендерит `.pic` (OCIF, метод 6): `python3 render.py home/images/reactorGUI.pic bg.png`.

## API сценария (`__EMU__`)

| Функция | Что делает |
|---|---|
| `emu.addComponent(proxy)` / `emu.removeComponent(proxy)` | подключить или отключить компонент (шлёт `component_added`/`component_removed`) |
| `emu.at(t, fn)` | выполнить `fn` в момент виртуального времени `t` |
| `emu.touch(x, y, nick)` | клик по экрану |
| `emu.chat(nick, msg)` | сообщение в чат-бокс |
| `emu.key(char, code)` | нажатие клавиши |
| `emu.dump(path)` | снять дамп экрана для `render.py` |
| `emu.screenText()` | текст экрана, удобно для проверок в тестах |
| `emu.endTime = t` | остановить прогон на времени `t` |
| `emu.run(path)` | запустить программу |

Состояние мока меняется напрямую, например `reactor.state.coolant = 0` или `me.state.fluid = 0`.

## Сценарии

| Сценарий | Что проверяет |
|---|---|
| `legacy_smoke.lua` | v1.1.3: эталонные скриншоты |
| `legacy_me_cooldown.lua` | баг v1.1.3: пауза ME останавливает все жидкостные реакторы |
| `legacy_refill_hiccup.lua` | баг v1.1.3: короткий перебой подачи останавливает реактор навсегда |
| `probe.lua` | зонд `tools/probe` на моках |
| `v2_smoke.lua` | v2 без интерфейса: защита, автозапуск, отключение реактора |
| `v2_gui.lua` | v2 с интерфейсом: скриншоты всех экранов, кнопки, настройки, тема |
| `install_v2.lua` | установщик v2 + перенос настроек со старой версии |

`emu.runVirtual(path, ...)` запускает программу по пути внутри песочницы, `emu.install(src, dst)` копирует каталог в песочницу.
