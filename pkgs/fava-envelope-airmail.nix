{
  lib,
  buildPythonPackage,
  beanquery,
  fava,
  pdm-backend,

  src,
}:
buildPythonPackage rec {
  pname = "fava-envelope-airmail";
  version = "2026.07.28";
  pyproject = true;

  # Fork of polarmutex/fava-envelope (MIT) with a budget stats view and a
  # colour-coded table; upstream dropped pandas, so this needs fava + beanquery
  # only.
  inherit src;

  build-system = [ pdm-backend ];

  dependencies = [
    beanquery
    fava
  ];

  meta = {
    description = "Envelope budgeting extension for Fava/Beancount";
    homepage = "https://github.com/stenius/fava-envelope-airmail";
    license = lib.licenses.mit;
  };
}
