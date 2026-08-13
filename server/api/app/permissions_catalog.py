"""Атомарные права. Код стабильный — на него опирается API."""

PERMISSIONS: list[tuple[str, str, str]] = [
    ("platform.manage", "Управление платформой", "platform"),
    ("company.manage", "Управление компанией", "company"),
    ("branches.manage", "Филиалы: создание и правка", "company"),
    ("roles.manage", "Роли и права", "company"),
    ("users.manage", "Пользователи компании", "company"),
    ("orders.read", "Заказы: просмотр", "orders"),
    ("orders.write", "Заказы: создание и правка", "orders"),
    ("orders.issue", "Заказы: выдача", "orders"),
    ("cash.read", "Касса: просмотр", "cash"),
    ("cash.write", "Касса: операции", "cash"),
    ("inventory.read", "Склад: просмотр", "inventory"),
    ("inventory.write", "Склад: движение", "inventory"),
]

# Базовые роли компании (не platform).
COMPANY_ROLE_PRESETS: dict[str, list[str]] = {
    "Администратор компании": [
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
    ],
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
