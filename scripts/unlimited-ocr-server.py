#!/usr/bin/env python3
"""百度 Unlimited-OCR-2（MLX 版）的本机 OpenAI 兼容接口，给 Tyto 截屏回复的"先用看图模型读图"用。

为什么不用 mlx-vlm 自带的 server：它在这个模型上每次都报
"There is no Stream(gpu, N) in current thread"（模型在一个线程里加载，在另一个线程里生成）。
这里加载和生成都在主线程里，一次处理一个请求，截屏回复够用。

准备（Unlimited-OCR-2 的支持还在合进 mlx-vlm，先装带这个支持的分支；2026-10-27 核对过，只改了这个模型自己的目录）：
    uv venv --python 3.12 ~/.tyto-ocr
    uv pip install --python ~/.tyto-ocr/bin/python \\
        "git+https://github.com/shuuul/mlx-vlm.git@223c2980fe4b48bd73faeb9e5bb1f1eacafffb49"
运行（第一次会下载模型，4 位版约 2.5 GB）：
    ~/.tyto-ocr/bin/python scripts/unlimited-ocr-server.py            # 默认 4 位版，端口 18780
    ~/.tyto-ocr/bin/python scripts/unlimited-ocr-server.py --model mlx-community/Unlimited-OCR-2-8bit
然后在 Tyto 里：模型与服务 → 添加「自定义接口」，地址 http://127.0.0.1:18780/v1，
看图用这个服务商，模型填 mlx-community/Unlimited-OCR-2-4bit；截屏回复选「先用看图模型读图」。
"""

import argparse
import base64
import json
import os
import tempfile
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

from mlx_vlm import generate, load
from mlx_vlm.prompt_utils import apply_chat_template

parser = argparse.ArgumentParser(description="Unlimited-OCR-2 (MLX) OpenAI-compatible server for Tyto")
parser.add_argument("--model", default="mlx-community/Unlimited-OCR-2-4bit")
parser.add_argument("--host", default="127.0.0.1")
parser.add_argument("--port", type=int, default=18780)
parser.add_argument("--max-tokens", type=int, default=8192)
args = parser.parse_args()

print(f"加载 {args.model} …", flush=True)
model, processor = load(args.model)
print(f"就绪：http://{args.host}:{args.port}/v1", flush=True)


def read_images(content):
    """把 OpenAI 格式里的 base64 图片写成临时文件，返回（文字, 图片路径）"""
    if isinstance(content, str):
        return content, []
    texts, paths = [], []
    for part in content:
        if part.get("type") == "text":
            texts.append(part.get("text", ""))
        elif part.get("type") == "image_url":
            url = part["image_url"]["url"]
            data = base64.b64decode(url.split(",", 1)[1] if url.startswith("data:") else url)
            handle, path = tempfile.mkstemp(suffix=".png", prefix="tyto-ocr-")
            with os.fdopen(handle, "wb") as file:
                file.write(data)
            paths.append(path)
    return " ".join(t for t in texts if t), paths


def run(request):
    text, paths = "", []
    for message in request.get("messages", []):
        if message.get("role") == "user":
            part_text, part_paths = read_images(message.get("content", ""))
            text = text or part_text
            paths += part_paths
    try:
        prompt = apply_chat_template(processor, model.config, text or "Multi page parsing.", num_images=len(paths))
        started = time.time()
        result = generate(model, processor, prompt, image=paths or None,
                          max_tokens=request.get("max_tokens") or args.max_tokens, temperature=0.0, verbose=False)
        output = getattr(result, "text", result)
        print(f"{len(paths)} 张图 → {len(output)} 字，{time.time() - started:.1f} 秒", flush=True)
        return output
    finally:
        for path in paths:
            os.remove(path)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send_json(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self.send_json(200, {"object": "list", "data": [{"id": args.model, "object": "model"}]})
        else:
            self.send_json(404, {"error": {"message": "not found"}})

    def do_POST(self):
        if not self.path.rstrip("/").endswith("/chat/completions"):
            self.send_json(404, {"error": {"message": "not found"}})
            return
        request = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        try:
            output = run(request)
        except Exception as error:  # 出错时把原因交给 Tyto 显示
            self.send_json(500, {"error": {"message": str(error)}})
            return
        if request.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            chunk = {"object": "chat.completion.chunk", "model": args.model,
                     "choices": [{"index": 0, "delta": {"content": output}, "finish_reason": "stop"}]}
            self.wfile.write(f"data: {json.dumps(chunk, ensure_ascii=False)}\n\ndata: [DONE]\n\n".encode())
        else:
            self.send_json(200, {"object": "chat.completion", "model": args.model,
                                 "choices": [{"index": 0, "message": {"role": "assistant", "content": output},
                                              "finish_reason": "stop"}]})


# 单线程：加载和生成都在这个线程里
HTTPServer((args.host, args.port), Handler).serve_forever()
