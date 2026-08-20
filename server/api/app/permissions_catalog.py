"""Атомарные права. Код стабильный — на него опирается API."""

PERMISSIONS: list[tuple[str, str, str]] = [
    ("platform.manage", "Управление платформой", "platform"),
    ("company.manage", "Управление компанией", "company"),
    ("branches.manage", "Филиалы: создание и правка", "company"),
    ("roles.manage", "Роли и права (должности)", "company"),
    ("users.manage", "Пользователи компании", "company"),
    ("orders.read", "Заказы: просмотр", "orders"),
    ("orders.write", "Заказы: создание и правка", "orders"),
    ("orders.issue", "Заказы: выдача", "orders"),
    ("cash.read", "Касса: просмотр", "cash"),
    ("cash.write", "Касса: операции", "cash"),
    ("inventory.read", "Склад: просмотр", "inventory"),
    ("inventory.write", "Склад: движение", "inventory"),
]

# Полный доступ студии (владелец / управляющий / админ) — всё, кроме platform.*.
_FULL_STUDIO: list[str] = [
    "company.manage",
    "branches.manage",
    "roles.manage",
    "users.manage",
    "orders.read",
    "orders.write",
    "orders.issue",
    "cash.read",
    "cash.write",
    "inventory.read",
    "inventory.write",
]

# Должности компании (имена = то, что видит пользователь).
# Несколько должностей на одного User — через user_roles (уже есть).
# Несколько цехов — через crm_masters.role CSV (уже есть).
COMPANY_ROLE_PRESETS: dict[str, list[str]] = {
    "Владелец": list(_FULL_STUDIO),
    "Управляющий": list(_FULL_STUDIO),
    "Администратор": list(_FULL_STUDIO),
    # Совместимость со старым сидом
    "Администратор компании": list(_FULL_STUDIO),
    "Приёмщик": [
        "orders.read",
        "orders.write",
        "orders.issue",
        "cash.read",
        "cash.write",
        "inventory.read",
    ],
    "Мастер": [
        "orders.read",
        "inventory.read",
    ],
}
