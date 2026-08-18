from datetime import datetime

from pydantic import BaseModel, Field


class CashRegisterOut(BaseModel):
    id: int
    company_id: int
    name: str
    money_type: str
    is_active: bool
    sort_order: int

    model_config = {"from_attributes": True}


class CashShiftBalanceOut(BaseModel):
    register_id: int
    register_name: str | None = None
    money_type: str | None = None
    opening: float
    expected: float | None = None
    fact: float | None = None
    difference: float | None = None


class CashShiftOut(BaseModel):
    id: int
    company_id: int
    branch_id: int
    status: str
    opened_at: datetime | None = None
    closed_at: datetime | None = None
    note: str = ""
    balances: list[CashShiftBalanceOut] = []


class CashShiftOpen(BaseModel):
    openings: dict[int, float] = {}
    note: str = Field(default="", max_length=2000)
    branch_id: int | None = None


class CashShiftClose(BaseModel):
    facts: dict[int, float] = {}
    note: str = Field(default="", max_length=2000)


class CashFlowCreate(BaseModel):
    type: str = Field(min_length=1, max_length=20)
    amount: float = Field(gt=0)
    category: str = Field(default="Прочее", max_length=80)
    method: str = Field(default="Наличные", max_length=40)
    register_id: int | None = None
    description: str = Field(default="", max_length=2000)
    note: str = Field(default="", max_length=2000)
    counterparty: str = Field(default="", max_length=200)
    master_id: int | None = None
    inventory_id: int | None = None
    inventory_qty: float = 0
    order_id: int | None = None
    template_key: str = Field(default="", max_length=80)


class CashFlowUpdate(BaseModel):
    type: str | None = Field(default=None, min_length=1, max_length=20)
    amount: float | None = Field(default=None, gt=0)
    category: str | None = Field(default=None, max_length=80)
    method: str | None = Field(default=None, max_length=40)
    register_id: int | None = None
    description: str | None = Field(default=None, max_length=2000)
    note: str | None = Field(default=None, max_length=2000)
    counterparty: str | None = Field(default=None, max_length=200)
    master_id: int | None = None
    inventory_id: int | None = None
    inventory_qty: float | None = None
    order_id: int | None = None
    template_key: str | None = Field(default=None, max_length=80)


class CashFlowOut(BaseModel):
    id: int
    type: str
    amount: float
    category: str
    method: str
    register_id: int
    shift_id: int
    description: str
    note: str
    counterparty: str = ""
    master_id: int | None = None
    inventory_id: int | None = None
    inventory_qty: float = 0
    order_id: int | None = None
    template_key: str = ""
    created_at: datetime | None = None
    master_name: str | None = None
    inventory_name: str | None = None

    model_config = {"from_attributes": True}


class CashPaymentCreate(BaseModel):
    order_id: int
    amount: float = Field(gt=0)
    method: str = Field(default="Наличные", max_length=40)
    register_id: int | None = None


class CashPaymentOut(BaseModel):
    id: int
    crm_order_id: int
    amount: float
    method: str
    register_id: int
    shift_id: int
    created_at: datetime | None = None
    is_voided: bool = False

    model_config = {"from_attributes": True}


class CashJournalEntry(BaseModel):
    kind: str
    id: int
    created_at: datetime | None = None
    amount: float
    method: str
    title: str
    shift_id: int
    register_id: int
    order_id: int | None = None
    flow_type: str | None = None
    is_voided: bool = False
    category: str = ""
    register_name: str = ""
