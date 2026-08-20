from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class LoginRequest(BaseModel):
    """login — email или телефон; email оставлен для совместимости."""
    password: str = Field(min_length=6)
    login: str | None = Field(default=None, min_length=3, max_length=255)
    email: EmailStr | None = None


class RefreshRequest(BaseModel):
    refresh_token: str


class PermissionOut(BaseModel):
    id: int
    code: str
    title: str
    group_name: str

    model_config = {"from_attributes": True}


class RoleOut(BaseModel):
    id: int
    name: str
    is_system: bool
    company_id: int | None
    permission_codes: list[str] = []

    model_config = {"from_attributes": True}


class RoleCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    permission_codes: list[str] = []


class RoleUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=120)
    permission_codes: list[str] | None = None


class BranchOut(BaseModel):
    id: int
    name: str
    company_id: int
    is_active: bool

    model_config = {"from_attributes": True}


class BranchCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)


class CompanyOut(BaseModel):
    id: int
    name: str
    slug: str
    is_active: bool

    model_config = {"from_attributes": True}


class CompanyCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    slug: str = Field(min_length=2, max_length=80)
    branch_name: str = Field(default="Основной филиал", min_length=2, max_length=200)
    ## Опционально сразу создать владельца студии (не platform admin).
    owner_email: EmailStr | None = None
    owner_password: str | None = Field(default=None, min_length=6)
    owner_full_name: str | None = Field(default=None, max_length=200)
    owner_phone: str | None = Field(default=None, max_length=32)


class CompanyCreatedOut(BaseModel):
    company: CompanyOut
    branch: BranchOut
    owner_user_id: int | None = None
    owner_email: str | None = None


class UserOut(BaseModel):
    id: int
    email: EmailStr
    phone: str | None = None
    full_name: str
    is_active: bool
    is_platform_admin: bool
    company_id: int | None
    roles: list[str] = []
    branch_ids: list[int] = []
    permissions: list[str] = []
    pending_assignment: bool = False
    master_id: int | None = None
    workshops: list[str] = []


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)
    full_name: str = Field(default="", max_length=200)
    phone: str | None = Field(default=None, max_length=32)
    role_ids: list[int] = []
    ## Удобнее для UI: имена должностей (Владелец / Управляющий / …).
    role_names: list[str] = Field(default_factory=list, max_length=8)
    branch_ids: list[int] = []
    workshops: list[str] = Field(default_factory=list, max_length=16)
    link_master: bool = True


class UserAssign(BaseModel):
    """Назначение должности / филиалов / цехов после «подключения»."""

    role_names: list[str] = Field(default_factory=list, max_length=8)
    branch_ids: list[int] = Field(default_factory=list)
    workshops: list[str] = Field(default_factory=list, max_length=16)
    ## Если True — создать/обновить CrmMaster и связать user.master_id.
    link_master: bool = True


class AccessRequest(BaseModel):
    """Самостоятельный запрос доступа к компании (ожидает назначение)."""

    email: EmailStr
    password: str = Field(min_length=6)
    full_name: str = Field(min_length=1, max_length=200)
    phone: str | None = Field(default=None, max_length=32)
    company_slug: str = Field(default="demo", min_length=2, max_length=80)


# --- CRM C1 ---


class CrmClientCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    phone: str = Field(default="", max_length=32)
    is_vip: bool = False


class CrmClientUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    phone: str | None = Field(default=None, max_length=32)
    is_vip: bool | None = None


class CrmClientOut(BaseModel):
    id: int
    company_id: int
    name: str
    phone: str
    is_vip: bool

    model_config = {"from_attributes": True}


class CrmCarCreate(BaseModel):
    client_id: int
    make_model: str = Field(min_length=1, max_length=200)
    plate: str = Field(default="", max_length=32)
    vin: str = Field(default="", max_length=64)
    category: str = Field(default="1", max_length=8)


class CrmCarUpdate(BaseModel):
    make_model: str | None = Field(default=None, min_length=1, max_length=200)
    plate: str | None = Field(default=None, max_length=32)
    vin: str | None = Field(default=None, max_length=64)
    category: str | None = Field(default=None, max_length=8)


class CrmCarOut(BaseModel):
    id: int
    company_id: int
    client_id: int
    make_model: str
    plate: str
    vin: str
    category: str

    model_config = {"from_attributes": True}


class CrmOrderItemIn(BaseModel):
    id: int | None = None
    name: str = Field(min_length=1, max_length=300)
    price: float = 0
    workshop: str = Field(default="", max_length=80)
    is_done: bool = False
    comment: str = Field(default="", max_length=2000)
    master_ids: str = Field(default="", max_length=200)
    start_time: str = Field(default="", max_length=32)
    end_time: str = Field(default="", max_length=32)
    parent_id: int | None = None


class CrmOrderItemOut(BaseModel):
    id: int
    name: str
    price: float
    workshop: str
    is_done: bool
    comment: str = ""
    master_ids: str = ""
    start_time: str = ""
    end_time: str = ""
    parent_id: int | None = None

    model_config = {"from_attributes": True}


class CrmOrderItemPatch(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=300)
    price: float | None = None
    workshop: str | None = Field(default=None, max_length=80)
    is_done: bool | None = None
    comment: str | None = Field(default=None, max_length=2000)
    master_ids: str | None = Field(default=None, max_length=200)
    start_time: str | None = Field(default=None, max_length=32)
    end_time: str | None = Field(default=None, max_length=32)
    parent_id: int | None = None


class CrmOrderCreate(BaseModel):
    client_id: int
    car_id: int
    branch_id: int | None = None
    status: str = Field(default="Принят в работу", max_length=80)
    notes: str = Field(default="", max_length=4000)
    due_date: str = Field(default="", max_length=32)
    start_time: str = Field(default="", max_length=32)
    end_time: str = Field(default="", max_length=32)
    end_date: str = Field(default="", max_length=32)
    client_notes: str = Field(default="", max_length=4000)
    client_visible_notes: str = Field(default="", max_length=4000)
    master_notes: str = Field(default="", max_length=4000)
    payment_method: str = Field(default="Наличные", max_length=40)
    discount_percent: float = 0
    discount_fixed: float = 0
    promo_code: str = Field(default="", max_length=80)
    master_ids: list[int] = []
    receptionist_id: int | None = None
    items: list[CrmOrderItemIn] = []


class CrmOrderUpdate(BaseModel):
    status: str | None = Field(default=None, max_length=80)
    notes: str | None = Field(default=None, max_length=4000)
    due_date: str | None = Field(default=None, max_length=32)
    start_time: str | None = Field(default=None, max_length=32)
    end_time: str | None = Field(default=None, max_length=32)
    end_date: str | None = Field(default=None, max_length=32)
    client_notes: str | None = Field(default=None, max_length=4000)
    client_visible_notes: str | None = Field(default=None, max_length=4000)
    master_notes: str | None = Field(default=None, max_length=4000)
    payment_method: str | None = Field(default=None, max_length=40)
    discount_percent: float | None = None
    discount_fixed: float | None = None
    promo_code: str | None = Field(default=None, max_length=80)
    handover_ready: bool | None = None
    handover_works: bool | None = None
    handover_payment: bool | None = None
    handover_keys: bool | None = None
    handover_inspect: bool | None = None
    handover_notified: bool | None = None
    tech_wash_start: str | None = Field(default=None, max_length=32)
    tech_wash_end: str | None = Field(default=None, max_length=32)
    is_workshop_completed: bool | None = None
    paid_amount: float | None = None
    car_id: int | None = None
    master_ids: list[int] | None = None
    receptionist_id: int | None = None
    items: list[CrmOrderItemIn] | None = None


class CrmOrderOut(BaseModel):
    id: int
    company_id: int
    branch_id: int
    client_id: int
    car_id: int
    status: str
    price: float
    paid_amount: float
    notes: str
    due_date: str
    start_time: str = ""
    end_time: str = ""
    end_date: str = ""
    client_notes: str = ""
    client_visible_notes: str = ""
    master_notes: str = ""
    payment_method: str = "Наличные"
    discount_percent: float = 0
    discount_fixed: float = 0
    promo_code: str = ""
    handover_ready: bool = False
    handover_works: bool = False
    handover_payment: bool = False
    handover_keys: bool = False
    handover_inspect: bool = False
    handover_notified: bool = False
    tech_wash_start: str = ""
    tech_wash_end: str = ""
    is_workshop_completed: bool = False
    master_ids: list[int] = []
    receptionist_id: int | None = None
    items: list[CrmOrderItemOut] = []
    client_name: str | None = None
    car_label: str | None = None

    model_config = {"from_attributes": True}


class CrmOrderEventCreate(BaseModel):
    event_text: str = Field(min_length=1, max_length=4000)


class CrmOrderEventOut(BaseModel):
    id: int
    order_id: int
    event_text: str
    created_at: datetime | None = None

    model_config = {"from_attributes": True}
