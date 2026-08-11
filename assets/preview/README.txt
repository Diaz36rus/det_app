Превью оклейки — ассеты
=======================

Структура (на будущее, когда появятся PNG-слои):

  vehicles/
    generic_sedan/
      meta.json
      views/
        side/
          body_base.png
          body_mask.png
          chrome_mask.png
          glass.png
          shadow.png
        rear_quarter/
          …
        front_quarter/
          …

Сейчас приложение рисует плейсхолдер-силуэт в коде
(PlaceholderPreviewRenderer). Когда положите слои —
подключим RasterPreviewRenderer без смены UI.

id кузова / камер / хрома — см. lib/preview/preview_config.dart
