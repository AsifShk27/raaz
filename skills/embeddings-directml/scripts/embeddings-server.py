import os
import time
import json
import logging
from typing import List, Union, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

import torch
import numpy as np
from transformers import AutoTokenizer, AutoModel

LOG_DIR = os.path.join(os.path.expanduser("~"), ".openclaw", "embeddings-directml")
os.makedirs(LOG_DIR, exist_ok=True)
LOG_PATH = os.path.join(LOG_DIR, "server.log")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.FileHandler(LOG_PATH), logging.StreamHandler()],
)
logger = logging.getLogger("embeddings-directml")

HOST = os.environ.get("EMBEDDINGS_HOST", "0.0.0.0")
PORT = int(os.environ.get("EMBEDDINGS_PORT", "8124"))
MODEL_ID = os.environ.get("EMBEDDINGS_MODEL", "BAAI/bge-base-en-v1.5")
DEVICE_REQ = os.environ.get("EMBEDDINGS_DEVICE", "directml").lower()
# Default to CLS pooling for BGE/MXBAI-family embedding models.
POOLING = os.environ.get("EMBEDDINGS_POOLING", "cls").lower()  # cls | mean
MAX_LENGTH = int(os.environ.get("EMBEDDINGS_MAX_LENGTH", "512"))
LOCAL_ONLY = os.environ.get("EMBEDDINGS_LOCAL_ONLY", "0").lower() in ("1", "true", "yes")
PRELOAD = os.environ.get("EMBEDDINGS_PRELOAD", "1").lower() in ("1", "true", "yes")

if LOCAL_ONLY:
    os.environ.setdefault("HF_HUB_OFFLINE", "1")

class EmbeddingRequest(BaseModel):
    model: Optional[str] = None
    input: Union[str, List[str]]
    encoding_format: Optional[str] = None
    user: Optional[str] = None

app = FastAPI(title="Embeddings DirectML", version="1.0.0")

_tokenizer = None
_model = None
_device = torch.device("cpu")
_device_kind = "cpu"


def resolve_device():
    global _device, _device_kind
    if DEVICE_REQ in ("directml", "dml"):
        try:
            import torch_directml
            if torch_directml.device_count() > 0:
                _device = torch_directml.device(0)
                _device_kind = "directml"
                return
        except Exception as e:
            logger.warning(f"DirectML init failed: {e}")
    _device = torch.device("cpu")
    _device_kind = "cpu"


def load_model():
    global _tokenizer, _model
    if _tokenizer is not None and _model is not None:
        return
    resolve_device()
    logger.info(f"Loading embeddings model: {MODEL_ID} on {_device_kind}")
    try:
        _tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, local_files_only=LOCAL_ONLY)
        _model = AutoModel.from_pretrained(MODEL_ID, local_files_only=LOCAL_ONLY)
        _model.eval()
        _model.to(_device)
        logger.info("Embeddings model loaded")
    except Exception as e:
        logger.exception("Failed to load embeddings model")
        raise


def mean_pooling(last_hidden, attention_mask):
    mask = attention_mask.unsqueeze(-1).expand(last_hidden.size()).float()
    masked = last_hidden * mask
    summed = torch.sum(masked, dim=1)
    counts = torch.clamp(mask.sum(dim=1), min=1e-9)
    return summed / counts


def embed_texts(texts: List[str]) -> List[List[float]]:
    load_model()
    with torch.no_grad():
        encoded = _tokenizer(
            texts,
            padding=True,
            truncation=True,
            max_length=MAX_LENGTH,
            return_tensors="pt",
        )
        encoded = {k: v.to(_device) for k, v in encoded.items()}
        model_output = _model(**encoded)
        if POOLING == "cls":
            embeddings = model_output.last_hidden_state[:, 0]
        else:
            embeddings = mean_pooling(model_output.last_hidden_state, encoded["attention_mask"])
        embeddings = torch.nn.functional.normalize(embeddings, p=2, dim=1)
        return embeddings.cpu().tolist()


def count_tokens(texts: List[str]) -> int:
    load_model()
    total = 0
    for text in texts:
        ids = _tokenizer.encode(text, truncation=True, max_length=MAX_LENGTH)
        total += len(ids)
    return total


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "model": MODEL_ID,
        "device": _device_kind,
        "pooling": POOLING,
    }


@app.on_event("startup")
async def preload_model():
    if not PRELOAD:
        return
    try:
        load_model()
    except Exception:
        logger.exception("Embeddings preload failed")


@app.post("/v1/embeddings")
async def embeddings(req: EmbeddingRequest):
    try:
        texts = req.input if isinstance(req.input, list) else [req.input]
        if not texts:
            raise HTTPException(status_code=400, detail="input is empty")
        vectors = embed_texts(texts)
        prompt_tokens = count_tokens(texts)
        data = [
            {"object": "embedding", "embedding": vec, "index": i}
            for i, vec in enumerate(vectors)
        ]
        return {
            "object": "list",
            "model": MODEL_ID,
            "data": data,
            "usage": {
                "prompt_tokens": prompt_tokens,
                "total_tokens": prompt_tokens,
            },
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Embedding request failed")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=HOST, port=PORT)
