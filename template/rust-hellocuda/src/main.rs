use cudarc::driver::{CudaContext, LaunchConfig, PushKernelArg};
use cudarc::nvrtc::compile_ptx;

/// Compiled at runtime with NVRTC, so `nix build` needs no GPU and no nvcc.
const KERNEL_SRC: &str = r#"
extern "C" __global__ void saxpy(float a, const float *x, const float *y, float *out, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) {
        out[i] = a * x[i] + y[i];
    }
}
"#;

const A: f32 = 3.0;
const X: f32 = 1.0;
const Y: f32 = 2.0;

fn expected() -> f32 {
    A * X + Y
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let ctx = CudaContext::new(0)?;
    println!("GPU: {}", ctx.name()?);

    let ptx = compile_ptx(KERNEL_SRC)?;
    let module = ctx.load_module(ptx)?;
    let saxpy = module.load_function("saxpy")?;

    let n = 1024i32;
    let stream = ctx.default_stream();
    let x = stream.clone_htod(&vec![X; n as usize])?;
    let y = stream.clone_htod(&vec![Y; n as usize])?;
    let mut out = stream.alloc_zeros::<f32>(n as usize)?;

    let cfg = LaunchConfig::for_num_elems(n as u32);
    let mut launch = stream.launch_builder(&saxpy);
    launch.arg(&A).arg(&x).arg(&y).arg(&mut out).arg(&n);
    unsafe { launch.launch(cfg) }?;

    let result = stream.clone_dtoh(&out)?;
    let want = expected();
    assert!(
        result.iter().all(|&v| (v - want).abs() < f32::EPSILON),
        "saxpy result mismatch"
    );
    println!("saxpy({A} * {X} + {Y}) on {n} elements: all == {want} ✓");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    // CPU-only test so `cargo test` passes without a GPU.
    #[test]
    fn expected_value() {
        assert_eq!(expected(), 5.0);
    }
}
