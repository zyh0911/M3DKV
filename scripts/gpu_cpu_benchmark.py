#!/usr/bin/env python
# coding: utf-8

import time, logging
import torch
from transformers import GPT2LMHeadModel, GPT2Tokenizer
from typing import List, Tuple, Union

# ---------- log ----------
log_file = "gpt2_decoding_attn_avg.log"
logging.basicConfig(
    filename=log_file,
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
console = logging.StreamHandler()
console.setLevel(logging.INFO)
logging.getLogger().addHandler(console)

# ---------- device ----------
device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"Using device: {device}")

# ---------- NVML(GPU) ----------
def get_power_usage() -> float:
    return 0.0

if device == "cuda":
    try:
        from py3nvml import py3nvml
        py3nvml.nvmlInit()
        _nvml_handle = py3nvml.nvmlDeviceGetHandleByIndex(0)

        def get_power_usage() -> float:            # type: ignore
            try:
                return py3nvml.nvmlDeviceGetPowerUsage(_nvml_handle) / 1e3
            except Exception:
                return 0.0
    except Exception as e:
        logging.warning(f"NVML initial fail: {e}")

# ---------- model & tokenizer ----------
model = GPT2LMHeadModel.from_pretrained("gpt2").to(device)
tokenizer = GPT2Tokenizer.from_pretrained("gpt2")
if tokenizer.pad_token is None:                
    tokenizer.pad_token = tokenizer.eos_token
model.eval()

# ---------- paramters ----------
n_params = sum(p.numel() for p in model.parameters())        # ≈1.244e8
flops_per_token = n_params * 2                               # MAC
logging.info(f"Model params  : {n_params:,}")
logging.info(f"FLOPs / token : {flops_per_token / 1e9:.3f} GFLOPs")

# ---------- hook ----------
_attn_records: List[Tuple[Union[torch.cuda.Event, float],
                          Union[torch.cuda.Event, float]]] = []

def _attn_pre_hook(module, inputs):
    if device == "cuda":
        evt = torch.cuda.Event(enable_timing=True); evt.record()
        module._start = evt                                  # type: ignore[attr-defined]
    else:
        module._start = time.perf_counter()                  # type: ignore[attr-defined]

def _attn_post_hook(module, inputs, output):
    if device == "cuda":
        evt_end = torch.cuda.Event(enable_timing=True); evt_end.record()
        _attn_records.append((module._start, evt_end))       # type: ignore[attr-defined]
    else:
        end_ts = time.perf_counter()
        _attn_records.append((module._start, end_ts))        # type: ignore[attr-defined]

for block in model.transformer.h:
    block.attn.register_forward_pre_hook(_attn_pre_hook, with_kwargs=False)
    block.attn.register_forward_hook(_attn_post_hook,  with_kwargs=False)


@torch.no_grad()
def decode_measure(prompt: str,
                   new_tokens: int = 1000,
                   batch_size: int = 1):
    _attn_records.clear()

    inp = tokenizer([prompt] * batch_size,
                    return_tensors="pt").to(device)
    if device == "cuda":
        torch.cuda.synchronize()
        evt_all_start = torch.cuda.Event(enable_timing=True); evt_all_start.record()
    else:
        t_start = time.perf_counter()
    p0 = get_power_usage()

    _ = model.generate(**inp,
                       max_new_tokens=new_tokens,
                       do_sample=False,
                       use_cache=True)

    if device == "cuda":
        evt_all_end = torch.cuda.Event(enable_timing=True); evt_all_end.record()
        torch.cuda.synchronize()
        total_time_ms = evt_all_start.elapsed_time(evt_all_end)      # type: ignore
    else:
        total_time_ms = (time.perf_counter() - t_start) * 1e3
    p1 = get_power_usage()

    # —— self-attention avg time —— #
    if device == "cuda":
        total_attn_ms = sum(s.elapsed_time(e) for s, e in _attn_records)  # type: ignore
    else:
        total_attn_ms = sum((e - s) * 1e3 for s, e in _attn_records)      # type: ignore
    avg_attn_ms = total_attn_ms / len(_attn_records)

    # —— throughput & power efficiency —— #
    total_flops = flops_per_token * new_tokens * batch_size
    tflops      = total_flops / (total_time_ms * 1e-3) / 1e12      # FLOPs/s → TFLOPS
    avg_power_w = (p0 + p1) / 2
    tflops_per_w= tflops / avg_power_w if avg_power_w > 0 else float("nan")

    # —— log —— #
    logging.info(f"== Generation finished on {device} ==")
    logging.info(f"Tokens generated                : {new_tokens}")
    logging.info(f"Total decode time (s)           : {total_time_ms/1e3:.3f}")
    logging.info(f"Average self-attn (single layer): {avg_attn_ms:.3f} ms")
    logging.info(f"Average self-attn (12 layers)  : {avg_attn_ms*12:.3f} ms")
    logging.info(f"Effective throughput            : {tflops:.3f} TFLOPS")
    logging.info(f"Energy efficiency               : {tflops_per_w:.3f} TFLOPS/W")

    return dict(
        avg_attn_ms=avg_attn_ms,
        decode_time_s=total_time_ms / 1e3,
        tflops=tflops,
        power_w=avg_power_w,
        tflops_per_w=tflops_per_w,
    )

# ---------- CLI ----------
if __name__ == "__main__":
    res = decode_measure("A cat runs past a dog", new_tokens=1000)

    print("\n======== Summary ========")
    print(f"Avg self-attention (1 layer) : {res['avg_attn_ms']:.3f} ms")
    print(f"Total decode time            : {res['decode_time_s']:.3f} s")
    print(f"Effective throughput         : {res['tflops']:.3f} TFLOPS")
    if device == 'cuda':
        print(f"Avg power                    : {res['power_w']:.2f} W")
        print(f"Energy efficiency            : {res['tflops_per_w']:.3f} TFLOPS/W")
    print(f"Log saved to                 : {log_file}")

