#! @runtimeShell@
# SPDX-License-Identifier: MIT
#
# Set a password for a specified user on a *mounted* NixOS root, in a way that
# is safe to run on a cross-architecture build host.
#
# The only "foreign" work done here is computing the password hash.  That uses
# the build host's mkpasswd (a front-end to crypt(3) via libxcrypt), which
# yields a portable hash string and never executes any target-architecture
# binary -- so this works when the target root is, say, aarch64 and the build
# host is x86_64.
#
# The resulting /etc/shadow entry is preserved by NixOS's own user-account
# activation (config/users.nix -> update-users-groups.pl) as long as the user is
# declared in the configuration and `users.mutableUsers` is left at its default
# of `true`.  (With `mutableUsers = false` the configured password wins and this
# tool's value is ignored, which is the intended behaviour.)

set -euo pipefail

mkpasswd=@mkpasswd@/bin/mkpasswd

usage() {
  cat <<USAGE
Usage: $0 --root <mounted-root> --user <username>
         ( --password <plaintext> | --password-file <path> | --password-hash <hash> )
         [ --type sha512|sha256|blowfish|bsdi|yescrypt|bcrypt ]
         [ --min <days> ] [ --max <days> ] [ --warn <days> ] [ --inactive <days> ]

Write a password for <username> into <mounted-root>/etc/shadow.

  --root            Mount point of the target root (required).
  --user            Username whose password to set (required).
  --password        Plaintext password (read from this argument).
  --password-file   File containing the plaintext password.
  --password-hash   A pre-computed password hash (e.g. \$6\$...).
  --type            Hash algorithm for --password/--password-file (default: sha512).
                    One of sha512, sha256, blowfish, bsdi, yescrypt, bcrypt;
                    availability depends on the build host's libxcrypt.
  --min/--max/--warn/--inactive
                    Optional shadow ageing fields (days).

Cross-arch safe: the only target-agnostic step is hashing on the build host.
USAGE
}

root=""
user=""
password=""
passwordFile=""
passwordHash=""
hashType="sha512"
minDays=""
maxDays=""
warnDays=""
inactiveDays=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --user) user="$2"; shift 2 ;;
    --password) password="$2"; shift 2 ;;
    --password-file) passwordFile="$2"; shift 2 ;;
    --password-hash) passwordHash="$2"; shift 2 ;;
    --type) hashType="$2"; shift 2 ;;
    --min) minDays="$2"; shift 2 ;;
    --max) maxDays="$2"; shift 2 ;;
    --warn) warnDays="$2"; shift 2 ;;
    --inactive) inactiveDays="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$root" ]; then echo "error: --root is required" >&2; usage >&2; exit 1; fi
if [ -z "$user" ]; then echo "error: --user is required" >&2; usage >&2; exit 1; fi

if [ -n "$password" ] && [ -n "$passwordFile" ]; then
  echo "error: use only one of --password / --password-file / --password-hash" >&2
  exit 1
fi
if [ -n "$passwordHash" ] && { [ -n "$password" ] || [ -n "$passwordFile" ]; }; then
  echo "error: use only one of --password / --password-file / --password-hash" >&2
  exit 1
fi
if [ -z "$password" ] && [ -z "$passwordFile" ] && [ -z "$passwordHash" ]; then
  echo "error: one of --password / --password-file / --password-hash is required" >&2
  exit 1
fi

# Determine the hash.
if [ -n "$passwordHash" ]; then
  hash="$passwordHash"
else
  if [ -n "$passwordFile" ]; then
    if [ ! -f "$passwordFile" ]; then
      echo "error: password file not found: $passwordFile" >&2
      exit 1
    fi
    # Read the first line, stripping a trailing newline if present.
    pw=$(sed -n '1p' "$passwordFile" | tr -d '\n')
  else
    pw="$password"
  fi
  # Hash on the build host with mkpasswd (a front-end to crypt(3)).  Passed
  # via stdin so the plaintext never lands in the process table; mkpasswd
  # generates a random salt.  Method availability depends on the build host's
  # libxcrypt (nixpkgs's default "strong" build omits sha256crypt/bsdicrypt);
  # for hashes it does not provide, pass --password-hash with a pre-computed
  # value instead.
  case "$hashType" in
    sha512)   method="sha512crypt" ;;
    sha256)   method="sha256crypt" ;;
    blowfish) method="bcrypt" ;;
    bsdi)     method="bsdicrypt" ;;
    yescrypt) method="yescrypt" ;;
    bcrypt)   method="bcrypt" ;;
    *) echo "error: unsupported --type: $hashType" >&2; exit 1 ;;
  esac
  hash=$(printf '%s' "$pw" | "$mkpasswd" -m "$method" -s) || {
    echo "error: mkpasswd could not hash with method '$method' (the build host's" >&2
    echo "       libxcrypt may not provide it; use --password-hash for a pre-computed hash)" >&2
    exit 1
  }
  # Best-effort scrub of the plaintext from the shell variable.
  pw=""
fi

if [ -z "$hash" ]; then
  echo "error: failed to compute password hash" >&2
  exit 1
fi

root=$(readlink -f "$root")
shadow="$root/etc/shadow"
passwd="$root/etc/passwd"

mkdir -p "$(dirname "$shadow")"

# Sanity check: if /etc/passwd already exists, warn when the user is missing,
# because an undeclared user's shadow line is dropped at activation.
if [ -f "$passwd" ] && ! grep -q "^${user}:" "$passwd"; then
  echo "warning: '$user' is not present in $passwd; for the password to" >&2
  echo "         survive first boot, declare it via users.users.$user in the" >&2
  echo "         NixOS configuration (with users.mutableUsers = true)." >&2
fi

# Read the existing shadow (if any) and replace / append the user's line.
tmp=$(mktemp "${shadow}.tmp.XXXXXX")
found=0
if [ -f "$shadow" ]; then
  while IFS= read -r line; do
    # Skip blank lines.
    [ -z "$line" ] && continue
    field1="${line%%:*}"
    if [ "$field1" = "$user" ]; then
      # name:pwd:lstchg:min:max:warn:inact:expire:flag
      # Drop the first two fields (name + old password), keep the rest.
      rest="${line#*:*:}"
      # Replace password (field 2); keep the rest intact.
      echo "${user}:${hash}:${rest}" >> "$tmp"
      found=1
    else
      echo "$line" >> "$tmp"
    fi
  done < "$shadow"
fi

if [ "$found" -eq 0 ]; then
  # Build the ageing fields (empty => system defaults at activation).
  lstchg="1"
  line="${user}:${hash}:${lstchg}"
  line="${line}:${minDays:-}"
  line="${line}:${maxDays:-}"
  line="${line}:${warnDays:-}"
  line="${line}:${inactiveDays:-}"
  line="${line}:::"
  echo "$line" >> "$tmp"
fi

chmod 0600 "$tmp"
# NixOS's update-users-groups will chown to root:shadow on first boot; set a
# sensible owner here too in case the root is already live.
chown 0:0 "$tmp" 2>/dev/null || true

mv -f "$tmp" "$shadow"

echo "set password for user '$user' in $shadow"
