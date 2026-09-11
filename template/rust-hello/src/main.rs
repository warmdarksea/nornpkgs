use ferris_says::say;
use std::io::{stdout, BufWriter};

fn greeting() -> &'static str {
    "hello, world!"
}

fn main() {
    let out = stdout();
    let mut writer = BufWriter::new(out.lock());
    say(greeting(), 24, &mut writer).expect("failed to write greeting");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greeting_is_hello_world() {
        assert_eq!(greeting(), "hello, world!");
    }
}
