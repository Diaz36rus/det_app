from fastapi import FastAPI

app = FastAPI(title="Det App API", version="0.1.0")


@app.get("/health")
def health():
    return {"ok": True, "service": "det-app-api"}


@app.get("/")
def root():
    return {"name": "Det App API", "docs": "/docs"}
