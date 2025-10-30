{
  description = "NixOS development environment in Docker";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          name = "nix-dev-environment";
          
          buildInputs = with pkgs; [
            # Nix development tools
            nix
            nixpkgs-fmt
            nil
            alejandra
            nix-prefetch-git
            nix-tree
            
            # Version control
            git
            gh
            
            # Development tools
            gnumake
            cmake
            gcc
            pkg-config
            
            # Editors
            vim
            neovim
            
            # Shell utilities
            tmux
            fzf
            ripgrep
            fd
            bat
            eza
            jq
            yq-go
            
            # Docker tools
            docker-client
            docker-compose
          ];
          
          shellHook = ''
            echo "🚀 Nix development environment (flake) loaded!"
            echo ""
            echo "Available commands:"
            echo "  nix build       - Build the project"
            echo "  nix develop     - Enter development shell"
            echo "  nix flake check - Check flake"
            echo "  nix flake update - Update dependencies"
            echo ""
          '';
        };
      }
    );
}
