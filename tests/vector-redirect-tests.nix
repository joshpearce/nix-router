{ pkgs, vectorSettings }:
let
  config = (pkgs.formats.json { }).generate "vector-redirect-tests.json" vectorSettings;
in
pkgs.runCommand "vector-redirect-tests" { nativeBuildInputs = [ pkgs.vector ]; } ''
  vector validate --no-environment ${config}
  vector test ${config}
  touch "$out"
''
