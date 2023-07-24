{ lib
, stdenv
, fetchFromGitHub
, gitMinimal
, cacert
, yarn
, makeBinaryWrapper
, nodejs
, nodePackages
, python3
, nixosTests
}: let

  version = "1.9.8";

  src = fetchFromGitHub {
    owner = "hedgedoc";
    repo = "hedgedoc";
    rev = version;
    hash = "sha256-gp1TeYHwH7ffaSMifdURb2p+U8u6Xs4JU4b4qACEIDw=";
  };

  offlineCache = stdenv.mkDerivation {
    name = "hedgedoc-${version}-offline-cache";
    inherit src;

    nativeBuildInputs = [
      cacert # needed for git
      gitMinimal # needed for a dep
      nodePackages.npm # needed for a dep
      yarn
    ];

    HOME = "$TMPDIR";
    buildPhase = ''
      yarn config set enableTelemetry 0
      yarn config set cacheFolder $out
      yarn
    '';

    outputHashMode = "recursive";
    outputHash = "sha256-4TPc9J9u0rO9WfZVbFWwVAM5WY3n5zJdhIlNYiZNRoM=";
  };

in stdenv.mkDerivation rec {
  pname = "hedgedoc";
  inherit version src;

  nativeBuildInputs = [
    makeBinaryWrapper
    yarn
    python3 # needed for sqlite node-gyp
  ];

  dontConfigure = true;

  HOME = "$TMPDIR";
  buildPhase = ''
    runHook preBuild

    yarn config set enableTelemetry 0
    yarn config set cacheFolder ${offlineCache}

    # This will fail but create the sqlite3 files we can patch
    yarn --immutable-cache || :

    # Ensure we don't download any node things
    sed -i 's:--fallback-to-build:--build-from-source --nodedir=${nodejs}/include/node:g' node_modules/sqlite3/package.json
    export CPPFLAGS="-I${nodejs}/include/node"

    # Perform the actual install
    yarn --immutable-cache
    yarn run build

    patchShebangs bin/*

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -R {app.js,bin,lib,locales,node_modules,package.json,public} $out

    makeWrapper ${nodejs}/bin/node $out/bin/hedgedoc \
      --add-flags $out/app.js \
      --set NODE_ENV production \
      --set NODE_PATH "$out/lib/node_modules"

    runHook postInstall
  '';

  passthru = {
    tests = { inherit (nixosTests) hedgedoc; };
  };

  meta = with lib; {
    description = "Realtime collaborative markdown notes on all platforms";
    license = licenses.agpl3;
    homepage = "https://hedgedoc.org";
    maintainers = with maintainers; [ SuperSandro2000 ];
    platforms = platforms.linux;
  };
}
