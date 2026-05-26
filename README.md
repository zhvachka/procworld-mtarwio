# procworld + mtarwio

Два MTA:SA ресурса:

- **`procworld/`** — процедурный ландшафт (heightmap по шуму Перлина → DFF+COL чанков). См. [procworld/README.md](procworld/README.md).
- **`mtarwio/`** — клиентская библиотека для сборки RW-структур (DFF/TXD/COL) из Lua. Зависимость `procworld`.

## Установка

Скопируйте обе папки в `[your-resources]/` сервера MTA:SA и запустите:

```
start mtarwio
start procworld
```

В чате клиента: `/pwgen` — сгенерировать мир.
