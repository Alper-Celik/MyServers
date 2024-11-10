{
  lib,
  buildPythonPackage,
  octodns,
  pytestCheckHook,
  pythonOlder,
  setuptools,
  requests,

  src,
}:
buildPythonPackage rec {
  pname = "octodns-cloudflare";
  version = "0.0.0";
  pyproject = true;

  inherit src;

  nativeBuildInputs = [
    setuptools
  ];

  propagatedBuildInputs = [
    octodns
    requests
  ];

}
