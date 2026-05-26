# procworld

Процедурный ландшафт для MTA:SA. Делит мир на N×N чанков, для каждого по шуму Перлина строит heightmap → DFF + COL через [mtarwio](../mtarwio/), грузит как `createObject(..., isLowLOD)`.

**Зависит от:** `mtarwio`.

## Старт

`/pwgen` — сгенерировать и телепортироваться. `/pwclear` — снести.

Команды доступны через `example.lua`. Удалите его из `meta.xml`, чтобы использовать как чистую библиотеку.

## API

```lua
procworld.start(cfg, onComplete)
procworld.stop()
procworld.isActive()
procworld.getSpawn()
procworld.teleportPlayer(player)
procworld.returnPlayer(player)
procworld.getConfig()
```

## Конфиг

См. `config.lua`. Ключевое:

| Поле | Default | Что делает |
|---|---|---|
| `chunksPerSide × chunkSize` | 13 × 256 | Размер мира |
| `chunkResolution` | 24 | Полигональность чанка |
| `lodEnabled` / `lodResolution` | true / 24 | LOD-меш для горизонта |
| `noise.seed` | 1337 | Воспроизводимость |
| `colSurface` | `{material=4, brightness=0, light=0}` |
| `materialLighting` | `{ambient=0.85, diffuse=1.0, specular=0}` | RW material lighting |
| `detailTexture.size` | 256 | Размер процедурной текстуры |
| `vegetation.enabled` | true | Деревья/камни/кусты |