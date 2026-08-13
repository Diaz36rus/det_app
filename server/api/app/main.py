from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.db import Base, SessionLocal, engine
from app.routers import auth, company, platform, updates
from app.seed import seed_database


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        seed_database(db)
    finally:
        db.close()
    yield


app = FastAPI(title="Det App API", version="0.3.0", lifespan=lifespan)
app.include_router(auth.router)
app.include_router(platform.router)
app.include_router(company.router)
app.include_router(updates.router)


@app.get("/health")
def health():
    return {"ok": True, "service": "det-app-api", "version": "0.3.0"}


@app.get("/")
def root():
    return {
        "name": "Det App API",
        "docs": "/docs",
        "health": "/health",
        "auth": "/auth/login",
        "updates": "/updates/latest.json",
    }
