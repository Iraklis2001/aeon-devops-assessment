from fastapi import FastAPI

app = FastAPI(title="aeon-api", version="1.0.0")


@app.get("/")
def root() -> dict[str, str]:
    return {"service": "api", "status": "ok"}


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
def readyz() -> dict[str, str]:
    return {"status": "ready"}
