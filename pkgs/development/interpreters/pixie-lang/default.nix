{ stdenv, runCommand, pixie }:

runCommand "pixie-lang" {
  inherit pixie;
  inherit (stdenv) shell;
} ''
  mkdir -p $out/bin
  ln -s $pixie/bin/pxi $out/bin/pixie-vm

  cat > $out/bin/pxi <<EOF
  #!$shell
  >&2 echo "[\$\$] WARNING: 'pxi' is a deprecated alias for 'pixie-vm', please update your scripts."
  exec $pixie/bin/pxi "\$@"
  EOF

  chmod +x $out/bin/pxi
''
