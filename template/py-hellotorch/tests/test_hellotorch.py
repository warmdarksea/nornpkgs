import torch


# CPU-only test so the suite passes without a GPU.
def test_torch_cpu_sum():
    assert torch.arange(10).sum().item() == 45
