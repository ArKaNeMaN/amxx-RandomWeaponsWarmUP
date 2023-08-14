# Random Weapons WarmUP

Форк плагина [[fork] Random Weapons WarmUP 2.4.9](https://dev-cs.ru/resources/384/) от [h1k3](https://dev-cs.ru/members/95/), который, в свою очередь, является форком плагина от neygomon'а.

## Отличия от оригинала

- Список выключаемых на время разминки плагинов вынесен в JSON файл `amxmodx/configs/plugins/RWW/DisablePlugins.json`;
- Список карт, на которых разминка работать не будет, вынесен в JSON файл `amxmodx/configs/plugins/RWW/IgnoredMaps.json`;
- Вместо хардкодного списка оружия добавлены режимы разминки, настраиваемые в JSON файле `amxmodx/configs/plugins/RWW/Modes.json`.
- Добавлены форварды `RWW_OnStarted` и `RWW_OnFinished`.

## Требования

- AmxModX версии 1.9.0 или новее;
- ReAPI желательно свежей версии;
- ItemsController из [VipModular](https://github.com/ArKaNeMaN/amxx-VipModular-pub/releases) (Ядро не требуется).

## Настройка режимов

Режимы разминки настраиваются в файле `amxmodx/configs/plugins/RWW/Modes.json`. Файл должен содержать массив обьектов режима разминки.

### Обьект режима разминки

#### Поля обьекта режима разминки

| Название  | Обязательное  | Описание
| :---      | :---          | :---
| Title     | Да            | Отображаемое назание режима разминки.
| Items     | Да            | Массив предметов для ItemsController, которые будут выдаваться всем игрокам.
| Music     | Нет           | Путь до `.mp3` файла, который будет проигрываться во время этого режима.

[Подробнее о структуре предметов для ItemcController...](https://github.com/ArKaNeMaN/amxx-VipModular-pub/blob/master/readme/items.md)

### Пример содержимого файла режимов разминки

```jsonc
[
    {
        "Title": "Разминка на AK47/M4A1 + Deagle",
        "Items": [
            {
                "Type": "Random",
                "Items": [
                    {
                        "Type": "Weapon",
                        "Name": "weapon_m4a1"
                    },
                    {
                        "Type": "Weapon",
                        "Name": "weapon_ak47"
                    }
                ],
            },
            {
                "Type": "Weapon",
                "Name": "weapon_deagle"
            }
        ]
    },
    {
        "Title": "Разминка на гранатах",
        "Music": "sound/rww/RoundStart.mp3",
        "Items": [
            {
                "Type": "Weapon",
                "Name": "weapon_hegrenade",
                "BpAmmo": 99
            }
        ]
    }
]
```
