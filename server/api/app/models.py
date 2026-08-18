from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


class Company(Base):
    __tablename__ = "companies"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    slug: Mapped[str] = mapped_column(String(80), unique=True, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    branches: Mapped[list[Branch]] = relationship(back_populates="company")
    roles: Mapped[list[Role]] = relationship(back_populates="company")
    users: Mapped[list[User]] = relationship(back_populates="company")
    crm_clients: Mapped[list[CrmClient]] = relationship(back_populates="company")
    crm_orders: Mapped[list[CrmOrder]] = relationship(back_populates="company")


class Branch(Base):
    __tablename__ = "branches"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    company: Mapped[Company] = relationship(back_populates="branches")


class Permission(Base):
    __tablename__ = "permissions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    code: Mapped[str] = mapped_column(String(80), unique=True, nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    group_name: Mapped[str] = mapped_column(String(80), default="general", nullable=False)


class Role(Base):
    __tablename__ = "roles"
    __table_args__ = (UniqueConstraint("company_id", "name", name="uq_role_company_name"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int | None] = mapped_column(ForeignKey("companies.id"), nullable=True, index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    is_system: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    company: Mapped[Company | None] = relationship(back_populates="roles")
    permissions: Mapped[list[Permission]] = relationship(secondary="role_permissions")


class RolePermission(Base):
    __tablename__ = "role_permissions"
    __table_args__ = (UniqueConstraint("role_id", "permission_id", name="uq_role_perm"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    role_id: Mapped[int] = mapped_column(ForeignKey("roles.id", ondelete="CASCADE"), nullable=False)
    permission_id: Mapped[int] = mapped_column(ForeignKey("permissions.id", ondelete="CASCADE"), nullable=False)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    phone: Mapped[str | None] = mapped_column(String(20), unique=True, nullable=True, index=True)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    full_name: Mapped[str] = mapped_column(String(200), default="", nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_platform_admin: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    company_id: Mapped[int | None] = mapped_column(ForeignKey("companies.id"), nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    company: Mapped[Company | None] = relationship(back_populates="users")
    roles: Mapped[list[Role]] = relationship(secondary="user_roles")
    branches: Mapped[list[Branch]] = relationship(secondary="user_branches")


class UserRole(Base):
    __tablename__ = "user_roles"
    __table_args__ = (UniqueConstraint("user_id", "role_id", name="uq_user_role"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    role_id: Mapped[int] = mapped_column(ForeignKey("roles.id", ondelete="CASCADE"), nullable=False)


class UserBranch(Base):
    __tablename__ = "user_branches"
    __table_args__ = (UniqueConstraint("user_id", "branch_id", name="uq_user_branch"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    branch_id: Mapped[int] = mapped_column(ForeignKey("branches.id", ondelete="CASCADE"), nullable=False)


class CrmClient(Base):
    """Клиент студии (облако C1)."""

    __tablename__ = "crm_clients"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    phone: Mapped[str] = mapped_column(String(32), default="", nullable=False)
    is_vip: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    company: Mapped[Company] = relationship(back_populates="crm_clients")
    cars: Mapped[list[CrmCar]] = relationship(back_populates="client", cascade="all, delete-orphan")


class CrmCar(Base):
    __tablename__ = "crm_cars"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    client_id: Mapped[int] = mapped_column(ForeignKey("crm_clients.id", ondelete="CASCADE"), nullable=False, index=True)
    make_model: Mapped[str] = mapped_column(String(200), nullable=False)
    plate: Mapped[str] = mapped_column(String(32), default="", nullable=False)
    vin: Mapped[str] = mapped_column(String(64), default="", nullable=False)
    category: Mapped[str] = mapped_column(String(8), default="1", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    client: Mapped[CrmClient] = relationship(back_populates="cars")


class CrmOrder(Base):
    __tablename__ = "crm_orders"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    branch_id: Mapped[int] = mapped_column(ForeignKey("branches.id"), nullable=False, index=True)
    client_id: Mapped[int] = mapped_column(ForeignKey("crm_clients.id"), nullable=False, index=True)
    car_id: Mapped[int] = mapped_column(ForeignKey("crm_cars.id"), nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(80), default="Принят в работу", nullable=False)
    price: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    paid_amount: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    notes: Mapped[str] = mapped_column(Text, default="", nullable=False)
    due_date: Mapped[str] = mapped_column(String(32), default="", nullable=False)
    start_time: Mapped[str] = mapped_column(String(16), default="", nullable=False)
    end_time: Mapped[str] = mapped_column(String(16), default="", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    company: Mapped[Company] = relationship(back_populates="crm_orders")
    items: Mapped[list[CrmOrderItem]] = relationship(
        back_populates="order", cascade="all, delete-orphan"
    )
    master_links: Mapped[list[CrmOrderMaster]] = relationship(
        cascade="all, delete-orphan"
    )

class CrmOrderItem(Base):
    __tablename__ = "crm_order_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    order_id: Mapped[int] = mapped_column(
        ForeignKey("crm_orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(300), nullable=False)
    price: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    workshop: Mapped[str] = mapped_column(String(80), default="", nullable=False)
    is_done: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    order: Mapped[CrmOrder] = relationship(back_populates="items")


class CrmMaster(Base):
    __tablename__ = "crm_masters"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    role: Mapped[str] = mapped_column(String(80), default="Универсал", nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)


class CrmService(Base):
    __tablename__ = "crm_services"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    category: Mapped[str] = mapped_column(String(80), default="Прочее", nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    price: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    workshop: Mapped[str] = mapped_column(String(80), default="", nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)


class CrmOrderMaster(Base):
    __tablename__ = "crm_order_masters"
    __table_args__ = (UniqueConstraint("order_id", "master_id", name="uq_order_master"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    order_id: Mapped[int] = mapped_column(
        ForeignKey("crm_orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    master_id: Mapped[int] = mapped_column(ForeignKey("crm_masters.id"), nullable=False)


class CrmDefect(Base):
    __tablename__ = "crm_defects"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    order_id: Mapped[int] = mapped_column(
        ForeignKey("crm_orders.id", ondelete="CASCADE"), nullable=False, index=True
    )
    workshop: Mapped[str] = mapped_column(String(80), default="", nullable=False)
    description: Mapped[str] = mapped_column(Text, default="", nullable=False)
    photo_b64: Mapped[str] = mapped_column(Text, default="", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class CrmInventoryItem(Base):
    __tablename__ = "crm_inventory_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    quantity: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    unit: Mapped[str] = mapped_column(String(20), default="шт", nullable=False)
    category: Mapped[str] = mapped_column(String(80), default="Прочее", nullable=False)
    min_qty: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)


class CrmInventoryMove(Base):
    __tablename__ = "crm_inventory_moves"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    item_id: Mapped[int] = mapped_column(
        ForeignKey("crm_inventory_items.id", ondelete="CASCADE"), nullable=False, index=True
    )
    delta: Mapped[float] = mapped_column(Float, nullable=False)
    balance_after: Mapped[float] = mapped_column(Float, nullable=False)
    reason: Mapped[str] = mapped_column(String(120), default="", nullable=False)
    order_id: Mapped[int | None] = mapped_column(ForeignKey("crm_orders.id"), nullable=True)
    note: Mapped[str] = mapped_column(Text, default="", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class CashRegister(Base):
    __tablename__ = "cash_registers"
    __table_args__ = (UniqueConstraint("company_id", "money_type", name="uq_cash_reg_company_type"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    money_type: Mapped[str] = mapped_column(String(40), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class CashShift(Base):
    __tablename__ = "cash_shifts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    branch_id: Mapped[int] = mapped_column(ForeignKey("branches.id"), nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(20), default="open", nullable=False)  # open|closed
    opened_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    note: Mapped[str] = mapped_column(Text, default="", nullable=False)
    opened_by_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)

    balances: Mapped[list[CashShiftBalance]] = relationship(
        back_populates="shift", cascade="all, delete-orphan"
    )


class CashShiftBalance(Base):
    __tablename__ = "cash_shift_balances"
    __table_args__ = (UniqueConstraint("shift_id", "register_id", name="uq_shift_register"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    shift_id: Mapped[int] = mapped_column(
        ForeignKey("cash_shifts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    register_id: Mapped[int] = mapped_column(ForeignKey("cash_registers.id"), nullable=False)
    opening: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    expected: Mapped[float | None] = mapped_column(Float, nullable=True)
    fact: Mapped[float | None] = mapped_column(Float, nullable=True)
    difference: Mapped[float | None] = mapped_column(Float, nullable=True)

    shift: Mapped[CashShift] = relationship(back_populates="balances")


class CashFlow(Base):
    __tablename__ = "cash_flows"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    branch_id: Mapped[int] = mapped_column(ForeignKey("branches.id"), nullable=False, index=True)
    shift_id: Mapped[int] = mapped_column(ForeignKey("cash_shifts.id"), nullable=False, index=True)
    register_id: Mapped[int] = mapped_column(ForeignKey("cash_registers.id"), nullable=False)
    # Приход | Расход
    type: Mapped[str] = mapped_column(String(20), nullable=False)
    amount: Mapped[float] = mapped_column(Float, nullable=False)
    category: Mapped[str] = mapped_column(String(80), default="Прочее", nullable=False)
    method: Mapped[str] = mapped_column(String(40), default="Наличные", nullable=False)
    description: Mapped[str] = mapped_column(Text, default="", nullable=False)
    note: Mapped[str] = mapped_column(Text, default="", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    created_by_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)


class CashPayment(Base):
    __tablename__ = "cash_payments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    company_id: Mapped[int] = mapped_column(ForeignKey("companies.id"), nullable=False, index=True)
    branch_id: Mapped[int] = mapped_column(ForeignKey("branches.id"), nullable=False, index=True)
    shift_id: Mapped[int] = mapped_column(ForeignKey("cash_shifts.id"), nullable=False, index=True)
    register_id: Mapped[int] = mapped_column(ForeignKey("cash_registers.id"), nullable=False)
    crm_order_id: Mapped[int] = mapped_column(ForeignKey("crm_orders.id"), nullable=False, index=True)
    amount: Mapped[float] = mapped_column(Float, nullable=False)
    method: Mapped[str] = mapped_column(String(40), default="Наличные", nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    created_by_user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    is_voided: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
