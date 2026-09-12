{ pkgs, ... }:

{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "arn" (builtins.readFile ../arn.sh))
  ] ++ (with pkgs; [ fzf ]);
}
