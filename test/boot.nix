# checks.<system>.boot-<name>: the generic system of a host, booted as a NixOS
# test VM until its default target.
{ self, name }:
{
  name = "boot-${name}";
  # the systems set nixpkgs.overlays and nixpkgs.config themselves
  node.pkgsReadOnly = false;
  nodes.machine = { config, lib, ... }: {
    imports = [ self.nixosModules.gensokyo.systems.${name} ];
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    # the instance side of the VM
    system.stateVersion = lib.mkDefault config.system.nixos.release;
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    target = machine.succeed("systemctl get-default").strip()
    machine.wait_for_unit(target)
    failed = machine.execute("systemctl list-units --state=failed --no-legend --plain")[1].strip()
    print(f"${name}: reached {target}" + (f", failed units:\n{failed}" if failed else ", no failed units"))
  '';
}
