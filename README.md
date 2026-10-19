<div align="center">

<img src="src/assets/icons/logo.svg" width="96" alt="YAYMA" />

# YAYMA <sup>mod2</sup>

**Альтернативный клиент Яндекс Музыки для Android с обходом цензуры, плагинами и удалением треков из плейлиста**

<a href="https://github.com/Gafykin/YAYMA-android/releases/tag/1"><img src="https://img.shields.io/badge/%D0%A1%D0%BA%D0%B0%D1%87%D0%B0%D1%82%D1%8C-v2.5.2%20mod2-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Скачать YAYMA v2.5.2 mod2" /></a>

<a href="https://github.com/Gafykin/YAYMA-android/releases/tag/1"><img src="https://img.shields.io/badge/%D0%B2%D0%B5%D1%80%D1%81%D0%B8%D1%8F-v2.5.2%20mod2-E85D75?style=flat-square" alt="версия" /></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/%D0%BB%D0%B8%D1%86%D0%B5%D0%BD%D0%B7%D0%B8%D1%8F-GPL--3.0-blue?style=flat-square" alt="лицензия" /></a>
<img src="https://img.shields.io/badge/%D0%BF%D0%BB%D0%B0%D1%82%D1%84%D0%BE%D1%80%D0%BC%D0%B0-Android-3DDC84?style=flat-square&logo=android&logoColor=white" alt="платформа" />
<a href="https://github.com/DarkPlayOff/YAYMA"><img src="https://img.shields.io/badge/%D0%BE%D1%81%D0%BD%D0%BE%D0%B2%D0%B0%D0%BD%20%D0%BD%D0%B0-YAYMA-8A63D2?style=flat-square" alt="основан на YAYMA" /></a>
<a href="https://github.com/Gafykin/YAYMA-android/releases"><img src="https://img.shields.io/github/downloads/Gafykin/YAYMA-android/total?style=flat-square&label=%D1%81%D0%BA%D0%B0%D1%87%D0%B8%D0%B2%D0%B0%D0%BD%D0%B8%D0%B9" alt="скачиваний" /></a>

</div>

<br>

<table align="center">
  <tr>
    <td align="center" valign="top">
      <a href="png/photo_1_2026-10-18_20-23-59.jpg"><img src="png/photo_1_2026-10-18_20-23-59.jpg" width="250" alt="Плеер" /></a><br>
      <sub><b>Плеер</b></sub>
    </td>
    <td align="center" valign="top">
      <a href="png/photo_1_2026-10-18_20-26-38.jpg"><img src="png/photo_1_2026-10-18_20-26-38.jpg" width="250" alt="Плагины и обход цензуры" /></a><br>
      <sub><b>Плагины и обход цензуры</b></sub>
    </td>
    <td align="center" valign="top">
      <a href="png/photo_3_2026-10-18_20-23-59.jpg"><img src="png/photo_3_2026-10-18_20-23-59.jpg" width="250" alt="Меню трека" /></a><br>
      <sub><b>Меню трека</b></sub>
    </td>
  </tr>
</table>

---

## ✨ Что нового в mod2

| | Возможность | Описание |
|:-:|---|---|
| 🔊 | **Обход цензуры (FckCensor)** | Автозамена запикованных треков оригиналами по списку сообщества [FckCensorData](https://github.com/Hazzz895/FckCensorData). Включается в настройках, список обновляется сам или кнопкой «Обновить список замен». |
| 🎶 | **Плейлист играет сам** | Нажатие на трек в плейлисте больше не включает «Мою волну»: продолжает играть выбранный плейлист. |
| 🗑️ | **Убрать из плейлиста** | В меню «три точки» у трека внутри плейлиста есть пункт «Убрать из плейлиста». |
| 🔁 | **Замена трека** | В меню трека можно подменить аудио конкретного трека своей ссылкой или файлом и вернуть оригинал. |
| 🧩 | **Плагины** | Свои списки замен аудио: добавление по ссылке или из JSON-файла, включение и выключение, обновление, удаление. |
| ➕ | **«Добавить в плейлист» на главном экране** | Кнопка рядом с названием трека в плеере. |

> [!NOTE]
> Плагины PulseSync (в том числе оригинальный FckCensor) в YAYMA технически не запускаются: они рассчитаны на среду PulseSync. Идея FckCensor реализована в приложении нативно.

## 🚀 Установка

1. Откройте [страницу релиза v2.5.2 mod2](https://github.com/Gafykin/YAYMA-android/releases/tag/1) и скачайте APK. Если файлов несколько, для большинства современных телефонов нужен `arm64-v8a`.
2. Разрешите установку из неизвестных источников и установите APK.
3. Войдите в аккаунт Яндекса.
4. Включите автозамену: **Настройки → Обход цензуры → Автозамена запикованных треков**.

> [!IMPORTANT]
> Мод подписан другим ключом, чем оригинальный APK, поэтому поверх оригинала он не ставится. Сначала удалите оригинальное приложение (скачанные треки и настройки при этом будут потеряны).

### Свои плагины

**Настройки → Плагины → «По ссылке» или «Из файла».** Плагин — это JSON со списком «id трека → ссылка на аудио»:

```json
{
  "tracks": {
    "12345678": "https://example.com/track.mp3"
  }
}
```

Подходят также плоский словарь `{"id": "ссылка"}` и массив объектов `{"id": "...", "url": "..."}`.

> [!WARNING]
> Списки замен составляют сторонние люди: от них зависит, какое аудио и с каких серверов будет проигрываться. Подключайте только те списки, которым доверяете.

## 🛠️ Сборка из исходников

Подробная инструкция (GitHub Actions и локальная сборка) в [README-MOD.md](README-MOD.md). Кратко, в папке `src`:

```bash
flutter_rust_bridge_codegen generate
flutter build apk --release --split-per-abi
```

**Технологии:** Flutter (интерфейс) и Rust через Flutter Rust Bridge v2 (сеть, аудио, хранение данных).

## 📋 Базовые возможности YAYMA

- **Приватность** — никакой аналитики и слежки со стороны клиента
- **Тексты песен** — несколько источников (LrcLib, BetterLyrics, YouLyPlus), включая пословную синхронизацию
- **Интеграция с системой** — управление из шторки уведомлений, глобальные горячие клавиши и Discord Rich Presence на десктопе

## ⚠️ Предупреждение

**YAYMA** основан на [YaMusic](https://github.com/yamusic/yamusic) и использует неофициальное API, не предназначенное для публичного использования. Проект находится в стадии активной разработки. Пользуйтесь на свой страх и риск. Проект написан с помощью ИИ. Данная сборка — неофициальная модификация, не связанная с Яндексом.

## ❤️ Благодарности

- [DarkPlayOff](https://github.com/DarkPlayOff) — автор оригинального [YAYMA](https://github.com/DarkPlayOff/YAYMA), на котором основан мод
- [Vyfor](https://github.com/vyfor) — за исходный TUI-клиент [YaMusic](https://github.com/yamusic/yamusic) и библиотеку [yandex-music-rs](https://github.com/vyfor/yandex-music-rs)
- [Hazzz895](https://github.com/Hazzz895) — за идею и список замен [FckCensor](https://github.com/Hazzz895/FckCensor)
- [LrcLib](https://lrclib.net), [BetterLyrics](https://github.com/better-lyrics/better-lyrics), [YouLyPlus](https://github.com/ibratabian17/YouLyPlus) — за базы текстов песен

## 📄 Лицензия

Проект распространяется под лицензией [GPL-3.0](LICENSE), как и оригинальный YAYMA.
