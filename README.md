# 📅 Расписание уроков

Приложение для школьного расписания: **iPhone/iPad (.ipa)**, **Android (.apk)** и **Windows (.exe)** из одного кода.

## Возможности

- Вкладки по дням (Пн–Сб), при запуске открывается сегодняшний день
- Карточка «Сейчас»: текущий урок, сколько осталось до конца, что дальше; во время перемены — сколько до следующего урока
- Подсветка: текущий урок — зелёный, следующий — оранжевый, прошедшие — серые
- Перемены между уроками с длительностью
- Добавление, редактирование, удаление, перенос урока на другой день
- Подсказки предметов, автоподстановка кабинета и учителя
- Копирование дня, очистка дня, восстановление примера
- Экспорт/импорт расписания текстом — удобно перенести с компьютера на телефон
- На широком экране (Windows, планшет) — вся неделя сразу
- Тёмная тема, работает без интернета, данные хранятся на устройстве

## ⬇️ Скачать

Готовые файлы лежат в папке [`release/`](release):

| Платформа | Файл | Как установить |
|---|---|---|
| Android 7+ | [`Raspisanie.apk`](release/Raspisanie.apk) | Открыть файл, разрешить установку из неизвестных источников |
| Windows 10/11 | [`Raspisanie.exe`](release/Raspisanie.exe) | Просто запустить, установка не нужна. SmartScreen: «Подробнее» → «Выполнить в любом случае» |
| iPhone / iPad (iOS 14+) | [`Raspisanie.ipa`](release/Raspisanie.ipa) | Через AltStore, SideStore, Sideloadly, ESign или TrollStore — они подпишут приложение вашим Apple ID |

Все три собраны скриптом [`standalone/build.sh`](standalone/build.sh) прямо на Linux — без Android Studio, Xcode и Windows.

## Как это устроено

| Папка | Что внутри |
|---|---|
| `www/` | Само приложение (HTML/CSS/JS) — общий код для всех платформ |
| `android/` | Android-проект (Capacitor) |
| `ios/` | iOS-проект (Capacitor, Swift Package Manager) |
| `electron/` | Обёртка для Windows (Electron) |
| `assets/icon.png` | Исходная иконка 1024×1024 |
| `standalone/` | Лёгкие нативные обёртки и скрипт сборки всех трёх файлов на Linux |
| `release/` | Готовые `.apk`, `.exe`, `.ipa` |
| `ci/build.yml` | Альтернатива: сборка через GitHub Actions (Capacitor + Electron) |

## Сборка на Linux одной командой

```bash
standalone/build.sh            # всё сразу -> release/
standalone/build.sh apk exe    # только нужное
```

Что внутри:
- **Android** — `standalone/android/`: одна Activity с WebView (smali), сборка apktool + подпись apksigner (v2/v3).
- **Windows** — `standalone/windows/main.cc`: окно на Microsoft Edge WebView2 (библиотека webview), кросс-компиляция Zig. Весь интерфейс встроен в exe, данные хранятся в `%LOCALAPPDATA%\Raspisanie`.
- **iOS** — `standalone/ios/main.m`: WKWebView, кросс-компиляция Zig с iPhoneOS SDK, ad-hoc подпись (`adhoc_sign.py`).

## Сборка через GitHub Actions (альтернатива)

1. Скопируйте содержимое `ci/build.yml` в `.github/workflows/build.yml`
   (на GitHub: открыть файл → ✏️ Edit → вставить → Commit).
2. Сборка запускается при push в `main`, в pull request, вручную (Actions → Run workflow)
   и при создании тега `v*`.
3. Готовые файлы — внизу страницы запуска в разделе **Artifacts**:
   - `Raspisanie-android-apk` → `Raspisanie.apk`
   - `Raspisanie-ios-ipa` → `Raspisanie.ipa`
   - `Raspisanie-windows-exe` → `Raspisanie-1.0.0-portable.exe` (без установки) и `Raspisanie-1.0.0-setup.exe` (установщик)
4. Если запушить тег, например `git tag v1.0.0 && git push origin v1.0.0`,
   все три файла автоматически попадут в **Releases**.

## Установка

- **Android:** откройте `Raspisanie.apk`, разрешите установку из неизвестных источников.
  APK подписан постоянным ключом (`android/app/schedule-release.p12`), поэтому новые версии ставятся поверх старых.
  Для публикации в Google Play замените ключ через секреты `ANDROID_KEYSTORE_*`.
- **iPhone/iPad:** `.ipa` собирается **без подписи** Apple. Установить можно через
  AltStore, SideStore, Sideloadly, TrollStore или переподписать своим сертификатом.
- **Windows:** запустите `portable.exe` или установщик. Если SmartScreen предупредит —
  «Подробнее» → «Выполнить в любом случае» (у exe нет платной подписи).

## Локальная разработка

```bash
npm install
npm run serve          # открыть http://localhost:8080 в браузере
npx cap sync           # скопировать www/ в android/ и ios/
npm run electron       # запустить версию для ПК
```
