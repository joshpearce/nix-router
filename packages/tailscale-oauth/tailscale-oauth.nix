{
  stdenv,
  curl,
  jq,
}:

stdenv.mkDerivation rec {
  name = "tailscale-oauth";
  version = "0.1.0";
  src = ./src;
  phases = "installPhase postInstall fixupPhase";
  buildInputs = [
    curl
    jq
  ];
  nativeBuildInputs = [ ];
  installPhase = ''
    mkdir -p $out/bin
    cp ${src}/ts-delete-node.sh $out/bin/ts-delete-node
    cp ${src}/ts-get-access-token.sh $out/bin/ts-get-access-token
    cp ${src}/ts-get-auth-key.sh $out/bin/ts-get-auth-key
    chmod +x $out/bin/ts-delete-node
    chmod +x $out/bin/ts-get-access-token
    chmod +x $out/bin/ts-get-auth-key
  '';
  postInstall = ''
    for script in "ts-delete-node" "ts-get-access-token" "ts-get-auth-key"; do
      substituteInPlace $out/bin/$script \
        --replace "_curl_" "${curl}/bin/curl" \
        --replace "_jq_" "${jq}/bin/jq" \
        --replace "_out_" "$out"
    done
  '';
}
