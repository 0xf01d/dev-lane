#!/usr/bin/env bash
# Toolchain sanity check — runs inside the dev-lane container.
# Verifies opencode/nix and a hello-world for every bundled language.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
say()  { printf '\n=== %s ===\n' "$*"; }

say "versions"
opencode --version || fail "opencode --version"
nix --version || fail "nix --version"
python3 --version
go version
rustc --version
cargo --version
elixir --version | grep -m1 Elixir
erl -noshell -eval 'io:format("Erlang/OTP ~s~n",[erlang:system_info(otp_release)]),halt().'
node --version
npm --version
git --version
tmux -V
jq --version

say "nix channel pin"
nix-channel --list | grep -q 'nixpkgs-unstable' || fail "channel nixpkgs-unstable not registered"
nix-channel --list

say "hello worlds"
d="$(mktemp -d)"; cd "$d"

printf '#include <stdio.h>\nint main(void){printf("hello-c\\n");return 0;}\n' > c.c
cc -O2 -o hello-c c.c && ./hello-c | grep -qx 'hello-c'

printf 'fn main() {\n    println!("hello-rust");\n}\n' > r.rs
rustc -O -o hello-rust r.rs && ./hello-rust | grep -qx 'hello-rust'

mkdir -p gohello && cd gohello
printf 'package main\nimport "fmt"\nfunc main(){ fmt.Println("hello-go") }\n' > main.go
printf 'module hello\ngo 1.24\n' > go.mod
GOFLAGS=-mod=mod go run . | grep -qx 'hello-go'
cd ..

elixir -e 'IO.puts "hello-elixir"' | grep -qx 'hello-elixir'

python3 -c 'print("hello-python")' | grep -qx 'hello-python'

node -e 'console.log("hello-node")' | grep -qx 'hello-node'

printf '#!/usr/bin/env bash\necho hello-bash\n' > hb.sh
bash hb.sh | grep -qx 'hello-bash'

cd /; rm -rf "$d"
printf '\nALL TOOLCHAIN CHECKS PASSED\n'
