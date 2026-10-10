{
  description = "Alpaka Desktop — native Linux Ollama client (Tauri v2 + Vue 3)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));

      # Native libraries required to build the Tauri v2 backend on Linux.
      # Mirrors the apt/pacman lists in CONTRIBUTING.md:26-43.
      tauriNativeBuildInputs = pkgs: with pkgs; [
        pkg-config
        patchelf
      ];

      tauriBuildInputs = pkgs: with pkgs; [
        # WebKitGTK / GTK stack
        webkitgtk_4_1
        gtk3
        glib
        glib-networking
        gdk-pixbuf
        cairo
        pango
        atk
        libsoup_3
        librsvg
        hicolor-icon-theme

        # Tray / indicator
        libayatana-appindicator

        # Wayland / X11
        wayland
        libxkbcommon

        # Crypto (keyring crate → crypto-openssl) + Secret Service (dbus)
        openssl
        dbus
      ] ++ lib.optionals stdenv.isLinux [
        xorg.libX11
        xorg.libXi
        xorg.libXcursor
        xorg.libXrandr
      ];
    in
    {
      devShells = forAllSystems (pkgs:
        let
          libs = tauriBuildInputs pkgs;
        in
        {
          default = pkgs.mkShell {
            name = "alpaka-desktop";

            nativeBuildInputs = (tauriNativeBuildInputs pkgs) ++ (with pkgs; [
              # Rust (src-tauri/Cargo.toml pins rust-version = 1.88.0)
              cargo
              rustc
              clippy
              rustfmt
              rust-analyzer

              # Node toolchain (package.json engines: node >=20, pnpm >=9)
              nodejs_22
              pnpm

              # Bundled SQLCipher (rusqlite) needs a C toolchain
              gcc
            ]);

            buildInputs = libs;

            # Expose the native libs so pkg-config and the linker can find them.
            PKG_CONFIG_PATH = pkgs.lib.makeSearchPathOutput "dev" "lib/pkgconfig" libs;
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libs;

            shellHook = ''
              echo "alpaka-desktop dev shell"
              echo "  rust  $(cargo --version | cut -d' ' -f2)"
              echo "  node  $(node --version)"
              echo "  pnpm  $(pnpm --version)"

              # Fork workaround: WebKitGTK 2.54.1 under native Wayland (e.g. mango/wlroots)
              # misreports the device scale factor (devicePixelRatio = -1/96, negative
              # innerWidth/Height). Every 100vw/100vh layout then collapses to zero and the
              # webview paints a blank window. Forcing the X11 backend runs the webview under
              # XWayland, where dpr is reported correctly. Drop this once WebKitGTK fixes its
              # Wayland scale-factor handling. See the fork's issue notes.
              export GDK_BACKEND=x11
              echo "  display  X11/XWayland (GDK_BACKEND=x11 — fork workaround for WebKitGTK Wayland dpr bug)"

              if [ ! -d node_modules ]; then
                echo "  → run 'pnpm install' to install frontend deps"
              fi
            '';
          };
        });
    };
}
