{
  description = "EMS Elixir Project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      perSystem = { config, self', inputs', pkgs, system, ... }:
        let
          inherit (pkgs) mkShell;
          # Use Erlang 28 with Elixir 1.20-rc.1, matching the system configuration
          beamPackages = pkgs.beam28Packages;
          elixir = beamPackages.elixir_1_20;
          version = "0.1.0";
        in
        {
          devShells = {
            default = mkShell {
              buildInputs = [
                elixir
                beamPackages.hex
                beamPackages.rebar3
                pkgs.postgresql
                pkgs.nodejs_20
                pkgs.bun
                pkgs.git
                pkgs.inotify-tools
              ];
              shellHook = ''
                export MIX_HOME=$PWD/.nix-mix
                export HEX_HOME=$PWD/.nix-hex
                export ERL_AFLAGS="-kernel shell_history enabled"
                export LANG=en_US.UTF-8
                export ERL_LIBS=""

                # Create mix and hex directories if they don't exist
                mkdir -p $MIX_HOME $HEX_HOME

                echo "Elixir development environment loaded"
                echo "Elixir version: $(elixir --version | head -n 1)"
                echo "Bun version: $(bun --version)"
              '';
            };
          };
          packages = {
            default = beamPackages.mixRelease {
              inherit version;
              pname = "ems_backend";
              src = ./backend;

              # Explicitly use Elixir 1.20
              inherit elixir;

              mixFodDeps = beamPackages.fetchMixDeps {
                pname = "ems-backend-deps";
                inherit version elixir;
                src = ./backend;
                sha256 = "sha256-gYPkJb946zAtPTwQJL7GWg8nlumZCsBpj+GPrRugN8o=";
              };
            };

            test = pkgs.stdenv.mkDerivation {
              name = "ems-backend-test";
              src = ./backend;

              nativeBuildInputs = [
                elixir
                beamPackages.hex
                beamPackages.rebar3
              ];

              buildInputs = [
                pkgs.postgresql
              ];

              # Ensure CA certificates are available
              NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

              buildPhase = ''
                export MIX_HOME=$TMPDIR/.mix
                export HEX_HOME=$TMPDIR/.hex
                export MIX_ENV=test
                export LANG=C.UTF-8
                export LC_ALL=C.UTF-8
                export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
                export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

                # Create Erlang SSL config to point to certificates
                mkdir -p $TMPDIR/ssl
                cat > $TMPDIR/ssl/ssl.config << EOF
                [{kernel, [
                  {cacertfile, "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"}
                ]}].
                EOF
                export ERL_FLAGS="-config $TMPDIR/ssl/ssl"

                # Install dependencies
                mix local.hex --force
                mix local.rebar --force
                mix deps.get --only test

                # Run tests
                mix test
              '';

              installPhase = ''
                mkdir -p $out
                touch $out/test-results.txt
                echo "Tests completed successfully" > $out/test-results.txt
              '';

              doCheck = true;
            };
          };

          apps = {
            default = {
              type = "app";
              program = "${pkgs.writeShellScript "run-ems" ''
                set -e

                # Colors for output
                RED='\033[0;31m'
                GREEN='\033[0;32m'
                YELLOW='\033[1;33m'
                BLUE='\033[0;34m'
                NC='\033[0m' # No Color

                # Setup environment
                export MIX_HOME=$PWD/.nix-mix
                export HEX_HOME=$PWD/.nix-hex
                export ERL_AFLAGS="-kernel shell_history enabled"
                export LANG=en_US.UTF-8
                export ERL_LIBS=""
                export PATH="${elixir}/bin:${beamPackages.hex}/bin:${beamPackages.rebar3}/bin:${pkgs.bun}/bin:${pkgs.postgresql}/bin:${pkgs.inotify-tools}/bin:$PATH"

                # Create necessary directories
                mkdir -p $MIX_HOME $HEX_HOME

                echo -e "''${GREEN}Starting EMS Application...''${NC}"

                # Function to cleanup background processes
                cleanup() {
                  echo -e "\n''${YELLOW}Shutting down services...''${NC}"
                  jobs -p | xargs -r kill 2>/dev/null
                  wait
                  echo -e "''${GREEN}Services stopped''${NC}"
                  exit 0
                }

                trap cleanup SIGINT SIGTERM

                # Check if we're in the project root
                if [ ! -d "backend" ] || [ ! -d "frontend" ]; then
                  echo -e "''${RED}Error: Must run from project root (EMS_Elixir directory)''${NC}"
                  exit 1
                fi

                # Install backend dependencies if needed
                cd backend
                echo -e "''${BLUE}[Backend]''${NC} Setting up dependencies..."
                mix local.hex --force --if-missing
                mix local.rebar --force --if-missing
                mix deps.get

                # Start backend
                echo -e "''${BLUE}[Backend]''${NC} Starting Phoenix server on http://localhost:4000"
                mix phx.server &
                BACKEND_PID=$!

                # Wait a moment for backend to start
                sleep 2

                # Install frontend dependencies if needed
                cd ../frontend
                echo -e "''${YELLOW}[Frontend]''${NC} Setting up dependencies..."
                if [ ! -d "node_modules" ]; then
                  bun install
                fi

                # Start frontend
                echo -e "''${YELLOW}[Frontend]''${NC} Starting Astro dev server"
                bun run dev &
                FRONTEND_PID=$!

                cd ..

                echo ""
                echo -e "''${GREEN}✓ Services started successfully!''${NC}"
                echo -e "  Backend:  ''${BLUE}http://localhost:4000''${NC}"
                echo -e "  Frontend: ''${YELLOW}http://localhost:4321''${NC}"
                echo ""
                echo -e "Press ''${RED}Ctrl+C''${NC} to stop all services"
                echo ""

                # Wait for all background jobs
                wait
              ''}";
            };
          };

          formatter = pkgs.nixpkgs-fmt;
        };
    };
}
