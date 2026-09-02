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
2. Карточка в консоли RuStore (тексты + скрины из `tools/RUSTORE_LISTING.md`)
3. Залить AAB, пройти модерацию
