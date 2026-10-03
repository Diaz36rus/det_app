from pydantic import BaseModel, Field


class CrmMasterCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    role: str = Field(default="Универсал", max_length=255)


class CrmMasterUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    role: str | None = Field(default=None, max_length=255)
    is_active: bool | None = None
    on_shift: bool | None = None


class CrmMasterOut(BaseModel):
    id: int
    company_id: int
    name: str
    role: str
    is_active: bool
    on_shift: bool = False

    model_config = {"from_attributes": True}


class CrmMasterOnShiftIn(BaseModel):
    on_shift: bool = True


class CrmServiceCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    category: str = Field(default="Прочее", max_length=80)
    price: float = 0
    price2: float = 0
    price3: float = 0
    price4: float = 0
    fixed_price: float = 0
    workshop: str = Field(default="", max_length=80)


class CrmServiceUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    category: str | None = None
    price: float | None = None
    price2: float | None = None
    price3: float | None = None
    price4: float | None = None
    fixed_price: float | None = None
    workshop: str | None = None
    is_active: bool | None = None


class CrmServiceOut(BaseModel):
    id: int
    company_id: int
    name: str
    category: str
    price: float
    price2: float = 0
    price3: float = 0
    price4: float = 0
    fixed_price: float = 0
    workshop: str
    is_active: bool

    model_config = {"from_attributes": True}


class CrmDefectCreate(BaseModel):
    workshop: str = Field(default="", max_length=80)
    description: str = Field(default="", max_length=4000)
    photo_b64: str = Field(default="", max_length=8_000_000)


class CrmDefectOut(BaseModel):
    id: int
    order_id: int
    workshop: str
    description: str
    photo_b64: str
    created_at: str | None = None

    model_config = {"from_attributes": True}


class CrmInventoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    quantity: float = 0
    unit: str = Field(default="шт", max_length=20)
    category: str = Field(default="Прочее", max_length=80)
    min_qty: float = 0
    meters_per_roll: float = 0
    unit_cost: float = 0


class CrmInventoryOut(BaseModel):
    id: int
    company_id: int
    name: str
    quantity: float
    unit: str
    category: str
    min_qty: float
    meters_per_roll: float = 0
    unit_cost: float = 0

    model_config = {"from_attributes": True}


class CrmInventoryMoveCreate(BaseModel):
    item_id: int
    delta: float
    reason: str = Field(default="adjust", max_length=120)
    order_id: int | None = None
    note: str = Field(default="", max_length=2000)


class CrmInventoryMoveOut(BaseModel):
    id: int
    item_id: int
    delta: float
    balance_after: float
    reason: str
    order_id: int | None = None
    note: str = ""

    model_config = {"from_attributes": True}


class CrmFilmRollCreate(BaseModel):
    inventory_id: int
    roll_number: str = Field(min_length=1, max_length=80)
    meters_initial: float | None = None


class CrmFilmRollOut(BaseModel):
    id: int
    company_id: int
    inventory_id: int
    roll_number: str
    meters_initial: float
    meters_left: float

    model_config = {"from_attributes": True}


class CrmWrapFilmOut(BaseModel):
    id: int
    name: str
    inventory_id: int
    stock_meters: float = 0
    meters_per_roll: float = 0
    inventory_category: str = ""
    unit: str = "м"


class CrmOrderWrapFilmIn(BaseModel):
    film_id: int
    roll_id: int | None = None
    meters: float = 0


class CrmOrderWrapFilmOut(BaseModel):
    id: int
    order_id: int
    film_id: int
    roll_id: int | None = None
    meters: float
    film_name: str = ""
    roll_number: str | None = None
    roll_meters_left: float | None = None
    inventory_id: int | None = None


class CrmOrderWrapFilmsPut(BaseModel):
    films: list[CrmOrderWrapFilmIn] = []


class CrmOrderWrapFilmsPutResult(BaseModel):
    warnings: list[str] = []
    films: list[CrmOrderWrapFilmOut] = []


class CrmInventoryUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    quantity: float | None = None
    unit: str | None = Field(default=None, max_length=20)
    category: str | None = Field(default=None, max_length=80)
    min_qty: float | None = None
    meters_per_roll: float | None = None
    unit_cost: float | None = None


class CrmRecipeOut(BaseModel):
    id: int
    service_name: str
    inventory_id: int
    qty: float
    inventory_name: str = ""
    unit: str = "шт"
    stock: float = 0
    unit_cost: float = 0


class CrmRecipeUpsert(BaseModel):
    service_name: str = Field(min_length=1, max_length=300)
    inventory_id: int
    qty: float = 1


class CrmRecipeApply(BaseModel):
    service_name: str = Field(min_length=1, max_length=300)
    order_id: int | None = None
    order_item_id: int | None = None


class CrmRecipeApplyResult(BaseModel):
    warnings: list[str] = []


class CrmImportClients(BaseModel):
    clients: list[dict] = []


class CrmStatsOut(BaseModel):
    revenue_today: float = 0
    revenue_month: float = 0
    revenue_period: float = 0
    orders_count: float = 0
    orders_period: float = 0
    avg_check: float = 0
    revenue_all: float = 0
    open_debt: float = 0
    open_orders: float = 0
    days: int = 30
    top_by_count: list[dict] = []
    top_by_revenue: list[dict] = []
    revenue_by_day: list[dict] = []
    by_status: list[dict] = []
    master_day: list[dict] = []
    master_day_date: str = ""
    owner_pulse: dict = {}
    by_lead_source: list[dict] = []
    margin_period: float = 0
    materials_period: float = 0
    payroll_period: float = 0


class CrmStudioLeadCreate(BaseModel):
    name: str = Field(default="", max_length=200)
    phone: str = Field(default="", max_length=32)
    car_label: str = Field(default="", max_length=200)
    lead_source: str = Field(default="", max_length=80)
    note: str = Field(default="", max_length=4000)
    status: str = Field(default="new", max_length=80)
    order_id: int | None = None


class CrmStudioLeadUpdate(BaseModel):
    name: str | None = Field(default=None, max_length=200)
    phone: str | None = Field(default=None, max_length=32)
    car_label: str | None = Field(default=None, max_length=200)
    lead_source: str | None = Field(default=None, max_length=80)
    note: str | None = Field(default=None, max_length=4000)
    status: str | None = Field(default=None, max_length=80)
    order_id: int | None = None


class CrmStudioLeadOut(BaseModel):
    id: int
    company_id: int
    name: str
    phone: str
    car_label: str
    lead_source: str
    note: str
    status: str
    order_id: int | None = None
    created_at: str | None = None
    updated_at: str | None = None

    model_config = {"from_attributes": True}


class CrmCarWarrantyCreate(BaseModel):
    car_id: int
    order_id: int | None = None
    kind: str = Field(default="", max_length=80)
    title: str = Field(default="", max_length=200)
    batch: str = Field(default="", max_length=120)
    started_at: str = Field(default="", max_length=32)
    months: int = 0
    ends_at: str = Field(default="", max_length=32)
    note: str = Field(default="", max_length=4000)
    reminder_sent: bool = False


class CrmCarWarrantyUpdate(BaseModel):
    car_id: int | None = None
    order_id: int | None = None
    kind: str | None = Field(default=None, max_length=80)
    title: str | None = Field(default=None, max_length=200)
    batch: str | None = Field(default=None, max_length=120)
    started_at: str | None = Field(default=None, max_length=32)
    months: int | None = None
    ends_at: str | None = Field(default=None, max_length=32)
    note: str | None = Field(default=None, max_length=4000)
    reminder_sent: bool | None = None


class CrmCarWarrantyOut(BaseModel):
    id: int
    company_id: int
    car_id: int
    order_id: int | None = None
    kind: str
    title: str
    batch: str
    started_at: str
    months: int
    ends_at: str
    note: str
    reminder_sent: bool
    created_at: str | None = None

    model_config = {"from_attributes": True}


class CrmWorkshopRoleCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)


class CrmWorkshopRoleOut(BaseModel):
    id: int
    company_id: int
    name: str

    model_config = {"from_attributes": True}


class CrmPromocodeCreate(BaseModel):
    code: str = Field(min_length=1, max_length=80)
    discount_percent: float = 0
    discount_fixed: float = 0
    is_active: bool = True


class CrmPromocodeOut(BaseModel):
    id: int
    company_id: int
    code: str
    discount_percent: float = 0
    discount_fixed: float = 0
    is_active: bool = True

    model_config = {"from_attributes": True}


class CrmPayrollRuleCreate(BaseModel):
    workshop: str = Field(min_length=1, max_length=80)
    service_name: str = Field(default="", max_length=300)
    mode: str = Field(default="percent", max_length=20)
    value: float = 0
    label: str = Field(default="", max_length=200)
    is_active: bool = True


class CrmPayrollRuleOut(BaseModel):
    id: int
    company_id: int
    workshop: str
    service_name: str
    mode: str
    value: float
    label: str
    is_active: bool

    model_config = {"from_attributes": True}


class CrmCarWarrantyUpcomingOut(CrmCarWarrantyOut):
    make_model: str = ""
    plate: str = ""
    client_name: str = ""
    client_phone: str = ""
