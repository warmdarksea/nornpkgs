{
  description = "NixOS system: furnace";

  inputs = {
    #
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    #emacs-overlay = {
      #  url = "github:nix-community/emacs-overlay";
      #  inputs.nixpkgs.follows = "nixpkgs";
      #};
      # home-manager = {
      #   url = "github:nix-community/home-manager";
      #   inputs.nixpkgs.follows = "nixpkgs";
      # };
      # lanzaboote = {
      #   url = "github:nix-community/lanzaboote/v0.4.2";
      #   inputs.nixpkgs.follows = "nixpkgs";
      # };

      #
      nix-gensokyo = {
        url = "path:/home/clownpiece/src/nix-gensokyo";
        flake = true;
        inputs.nixpkgs.follows = "nixpkgs";
      };    

      # fixup inputs
      # my-nixpkgs = {
        #   url = "path:/home/clownpiece/src/nixpkgs";
        #   flake = true;
        # };
        #my-nixos-hardware = {
          #  url = "path:/home/clownpiece/src/nixos-hardware";
          #  flake = true;
          #};
          #
          # fixpkgs_blender.url = "github:NixOS/nixpkgs/2af19cfb6aa40768c4bbefd801a136270e099191";
  };

  outputs = {
    self,

    nixpkgs,
    #nixos-hardware,
    # emacs-overlay,
    #home-manager,
    #lanzaboote,
    # nixpak,

    nix-gensokyo,

    # my-nixpkgs,
    # my-nixos-hardware,

    # fixpkgs_blender,
    ... }@inputs: {
      nixosConfigurations.hell = let
        system = "x86_64-linux";
        pkgs = nixpkgs.legacyPackages.${system};
        # licenseConfig = with nixpkgs; {
        #   allowlistedLicenses = with lib.licenses; [ bsl11 ];

        #   cudaSupport = true;
              
        #   allowUnfreePredicate = pkg: (builtins.elem (lib.getName pkg) [
        #     "nvidia-x11"
        #     "nvidia-persistenced"
        #     "nvidia-settings"
        #     #    "cuda_cudart"
        #     #    "cuda_cccl"
        #     #    "libcublas"
        #     #    "nvtop"
        #     "vcv-rack"
        #   ]) || (builtins.all (license:
        #   license.free || builtins.elem license.shortName [
        #     "CUDA EULA"
        #     #    "cuDNN EULA"
        #     #    "cuTENSOR EULA"
        #     "NVidia OptiX EULA"
        #   ]
        #   ) (if builtins.isList pkg.meta.license then pkg.meta.license else [ pkg.meta.license ]));
        # };
      in nixpkgs.lib.nixosSystem {
        system = "${system}";
        # specialArgs = {
          #   inherit nixpak;
          # };
          modules = [
            #lanzaboote.nixosModules.lanzaboote
            #nixos-hardware.nixosModules.asus-x13-flow
            ./configuration.nix
            ./hardware-configuration.nix
            nix-gensokyo.nixosModules.base
            # home-manager.nixosModules.home-manager {
            #   # home-manager.extraSpecialArgs = {
            #     # 
            #     # };

            #     home-manager.useUserPackages = true;
            #     home-manager.useGlobalPkgs = true;

            #     home-manager.users.clownpiece = nix-gensokyo.homeManagerModules.magician;
            #     home-manager.users.seiran = nix-gensokyo.homeManagerModules.common;
            # }

            # overlays
            # ({config, pkgs, lib, ...}:
            #   {
              #     nixpkgs.overlays = [(self: super: {
                #       blender = fixpkgs_blender.legacyPackages."x86_64-linux".blender;
                #     })];
                #   })
          ];
      };
    };
}
