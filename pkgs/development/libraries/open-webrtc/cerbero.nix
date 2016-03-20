{ runCommand, fetchFromGitHub
, python, perl, git }:

runCommand "openwebrtc-src-0" {
  src = fetchFromGitHub {
    owner = "EricssonResearch";
    repo = "cerbero";
    rev = "8d4fbddc9036659dc68967c6ddaa4207925d88b5";
    sha256 = "1nik80xr9raldrbclkiw5v58y7hzmcxx6lzk6pa14sgcbj78bsfz";
  };
  buildInputs = [ python perl git ];
} ''
  source $stdenv/setup
  eval unpackPhase
    
''

/* log


- adjust config/linux.cbo (has to be in format 'foo <b@a.r>')
- patch cerbero/utils/__init__.py to recognize arch (L 131)
- init git repo in install target


*/
