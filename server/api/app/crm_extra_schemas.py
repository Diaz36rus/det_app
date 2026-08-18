from pydantic import BaseModel, Field


class CrmMasterCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    role: str = Field(default="Универсал", max_length=80)


class CrmMasterUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    role: str | None = Field(default=None, max_length=80)
    is_active: bool | None = None


class CrmMasterOut(BaseModel):
    id: int
    company_id: int
    name: str
    role: str
    is_active: bool

    model_config = {"from_attributes": True}


class CrmServiceCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    category: str = Field(default="Прочее", max_length=80)
    price: float = 0
    workshop: str = Field(default="", max_length=80)


class CrmServiceUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    category: str | None = None
    price: float | None = None
    workshop: str | None = None
    is_active: bool | None = None


class CrmServiceOut(BaseModel):
    id: int
    company_id: int
    name: str
    category: str
    price: float
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


class CrmInventoryOut(BaseModel):
    id: int
    company_id: int
    name: str
    quantity: float
    unit: str
    category: str
    min_qty: float

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
    note: str

    model_config = {"from_attributes": True}


class CrmImportClients(BaseModel):
    clients: list[dict] = []
