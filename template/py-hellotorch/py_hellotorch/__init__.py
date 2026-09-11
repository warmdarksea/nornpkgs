import torch


def main() -> None:
    if not torch.cuda.is_available():
        raise SystemExit("CUDA is not available (torch.cuda.is_available() == False)")

    device = torch.device("cuda:0")
    print(f"torch {torch.__version__} on {torch.cuda.get_device_name(device)}")

    a = torch.randn(1024, 1024, device=device)
    b = torch.randn(1024, 1024, device=device)
    c = a @ b
    print(f"matmul: {tuple(a.shape)} @ {tuple(b.shape)} -> {tuple(c.shape)}, mean={c.mean().item():.4f}")

    x = torch.arange(10, device=device)
    print(f"sum(0..9) on GPU = {x.sum().item()}")

    torch.cuda.synchronize()
    print("hello, world! (from the GPU)")


if __name__ == "__main__":
    main()
