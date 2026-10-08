# Шлюпка спасения (Rescue Boat)

VPN-клиент для Windows для семьи и друзей. Некоммерческий, без рекламы, никуда не отправляет
аналитику и отчёты об ошибках.

Основан на [Hiddify](https://github.com/hiddify/hiddify-app) (v4.1.2) и его ядре
[hiddify-core](https://github.com/hiddify/hiddify-core). Ядро в нашей версии лежит в
[Rescue-boat-core](https://github.com/aeyota93-cloud/Rescue-boat-core). Оригинальное описание
Hiddify: [README_hiddify.md](README_hiddify.md).

*English: a Windows VPN client for family and friends, a non-commercial fork of Hiddify.
Changes are listed below.*

## Установка

1. Скачать `RescueBoat-Setup-x64.exe` в [релизах](https://github.com/aeyota93-cloud/Rescue-boat/releases).
   Портативная версия без установки: `RescueBoat-Portable-x64.zip`.
2. Windows может показать «Windows защитила ваш компьютер»: у программы нет платной цифровой
   подписи. Нажать «Подробнее» → «Выполнить в любом случае».
3. В программе «+» → вставить ссылку подписки (её выдаёт владелец сервера).
   Для режима VPN (весь трафик компьютера) программу нужно запускать от имени администратора.

## Что отличается от Hiddify

Приложение:
- Имя «Шлюпка спасения», `RescueBoat.exe`, своя иконка, свои папки и установщик: программа
  ставится рядом с Hiddify и не мешает ему.
- Отчёты об ошибках (Sentry) и аналитика выключены насовсем, переключатель убран.
- По умолчанию: регион «Россия» (российские сайты напрямую), Яндекс DNS для прямых запросов,
  локальная сеть мимо VPN, русский язык.
- «Настройки → Маршрутизация → Правила маршрутов»: свои правила для сайтов, IP, портов и
  программ (например, игра или торрент-клиент мимо VPN). Экран был в Hiddify, но не подключён.
- Ссылки вида `rescueboat://import/<ссылка подписки>`. Чужие схемы (`hiddify://`, `v2ray://` и
  другие) больше не перехватываются у других клиентов.
- Обновления и ссылки ведут в этот репозиторий.
- Сборка только Windows через GitHub Actions (`.github/workflows/windows.yml`), остальные
  workflow Hiddify удалены.
- `tools/make_icons.py`: все иконки из одного описания.

Ядро ([Rescue-boat-core](https://github.com/aeyota93-cloud/Rescue-boat-core)):
- Правила маршрутов из подписки (секции `route` и `dns` в формате sing-box) применяются:
  `direct` → напрямую, `block` → блок, остальное → через VPN. Hiddify их отбрасывал.
- Пользовательские правила применяются, в том числе по программам (`process_name`,
  `process_path`) — раздельное туннелирование на Windows.
- `RescueBoat.exe` мимо туннельной службы.

## Сборка

Только через GitHub Actions (условие лицензии Hiddify):
- push в `main` — сборка, файлы в артефакте запуска;
- тег `vX.Y.Z` — релиз; тег с дефисом (`v0.1.0-test`) — пре-релиз.

Версия ядра задаётся в `dependencies.properties` (`core.version`), ядро скачивается из релизов
Rescue-boat-core.

## Лицензия

[Hiddify Extended GPLv3](LICENSE.md), как у оригинала: открытый код, форк Hiddify на GitHub,
только некоммерческое использование. Hiddify — © Hiddify, все права на оригинальный код у авторов.
