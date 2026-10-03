# RuStore / Android release — package + signing

## Package ID
`ru.detapp.app` (было `com.example.det_app`)

После смены id на телефоне это **новое приложение** (старый debug `com.example…` можно удалить вручную).

## Release keystore (один раз)
```powershell
powershell -ExecutionPolicy Bypass -File tools\create_release_keystore.ps1
```
Создаст:
- `android/upload-keystore.jks`
- `android/key.properties`

Оба в `.gitignore`. **Бекап обязателен** — без ключа не обновить приложение в магазине.

## Сборка
```powershell
flutter build appbundle --release
flutter build apk --release
```
AAB → RuStore. APK → облачные обновления (тот же ключ).

## Дальше
1. ~~HTTPS для `api.det-app.ru`~~ — готово (`https://api.det-app.ru`, `https://det-app.ru`)
2. Карточка: `tools/rustore_listing.json` (тексты) + `tools/rustore_screens/`
3. Разово: ключ Public API в `tools/rustore_key.json` (из `rustore_key.example.json`)
4. Релиз в магазин: `tools\ship_store.ps1` (AAB собирается в том же проходе, `whatsNew` из патчноутов)
5. Подпись AAB в консоли RuStore должна быть уже загружена (иначе метод `/aab` откажет)
