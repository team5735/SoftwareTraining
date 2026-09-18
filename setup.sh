#!/bin/bash
set -e

function die {
    echo "$1"
    exit 1
}

function lookin {
    [[ ! -d "$1" ]] && return
    realpath "$1"/*
}

function kill_dists {
    set +e
    shopt -s nullglob
    wpilibs=()
    wpilibs+=($(lookin ~/.local/share/wpilib/))
    wpilibs+=($(lookin ~/wpilib/))
    [[ -z "$wpilibs" ]] && echo nothing installed && exit 0

    echo found the following installations:
    declare -i index=1
    for year in "${wpilibs[@]}"; do printf '(%d) WPILib at %s\n' $index "~${year#$HOME}"; index+=1; done
    read -p "choose one to delete; anything save a valid index cancels: " choice
    [[ "$choice" -lt 1 || "$choice" -gt "${#wpilibs[@]}" ]] && echo canceled && exit 0
    chosen="${wpilibs[$(( $choice - 1  ))]}"
    read -p "delete ~${chosen#$HOME} (y/N)? " may_delete
    [[ "$may_delete" != "y" ]] && echo nothing was changed && exit 0

    set -e
    where=$(realpath $chosen)
    rm -vrf $where
    year=$(basename "$where")
    rm -v ~/.local/share/applications/*"$year".desktop
    rm -v ~/Desktop/*"$year".desktop
    echo done~!
    exit 0
}

[[ -z "$1" ]] && die "make sure you copied the command correctly. i need to know which WPILib version to install"
[[ "$1" = "--kill" ]] && kill_dists

ver="$1"
[[ "${ver%%\.*}" -gt 2026 ]] && 2027_format=true

firstname="${USER%%_*}"
lastname="${USER##*_}"
while true; do
    echo name: "${firstname@u}" "${lastname@u}"
    email="${firstname@L}"_"${lastname@L}"@student.waylandps.org
    echo email: "$email"
    read -p "is this correct (Y/n)? " correct
    [[ -z "$correct" || "${correct@L}" == y ]] && break
    read -p "first name: " firstname
    read -p "last name: " lastname
done

needed=(wget pv pigz tar git gh libicu-dev libnspr4 libnss3 clang-format)
missing_pkgs=($(comm -23 <(printf '%s\n' "${needed[@]}" | sort) <(dpkg-query --show --showformat '${Package}\n')))
if [[ "$missing_pkgs" ]]; then
    echo installing "${#missing_pkgs[@]}" packages
    [[ "$2027_format" != true ]] && echo please stick around, you need to finish installation yourself
    sudo apt-get update
    sudo apt-get install --yes "${missing_pkgs[@]}"
    echo
fi

# has to come after package installation
git config --global user.name "${firstname@u} ${lastname@u}"
git config --global user.email "$email"

# $(compat a b) is a when installing a version >= 2027, otherwise b
function compat {
    [[ "$2027_format" = true ]] && echo "$1" || echo "$2"
}

set +e
dir="WPILib_$(compat Linux-x64 Linux)-$ver"
file="$dir.tar.gz"
url="https://packages.wpilib.workers.dev/installer/v$ver/$(compat "" Linux/)$file"
err="$(wget --spider "$url" 2>&1)"
[[ $? -ne 0 ]] && die $'seems like i can\'t download WPILib right now. try again later\nerror:\n\n'"$err"
set -e

echo downloading robot code to ~/FRC
if [[ ! -d ~/FRC ]]; then
    git clone https://github.com/team5735/FRC ~/FRC
    cat > ~/FRC/.git/hooks/pre-push <<'END'
#!/bin/bash
set -e -o pipefail
PS4=$'P \t$EPOCHREALTIME '

zeroes=$(git hash-object --stdin </dev/null | tr '[0-9a-f]' '0')

found_head=0
head="$(git rev-parse HEAD)"
while read local_ref local_id remote_ref remote_id; do
    # find HEAD
    [[ "$local_id" = "$zeroes" ]] && continue
    [[ "$local_id" != "$head" ]] && continue

    "$(git rev-parse --show-toplevel)"/format.java.sh --no-ask
    found_head=1
done
END
    chmod +x ~/FRC/.git/hooks/pre-push
else
    cat <<END
~/FRC is already present, not overwriting
to redownload the repository, you can run the setup script again
if you don't want to, run this command; you'll be missing the pre-push hook, though
rm -rf ~/FRC; git clone https://github.com/team5735/FRC ~/FRC
END
fi
echo

if ! git config get credential.https://github.com.helper >/dev/null 2>&1; then
    echo logging into GitHub. if you do not have an account you can make it now
    echo to copy the one-time-code, select it and use Ctrl+Shift+C
    echo unless you know better, you will want to authenticate git with your github credentials
    trap "echo cancelled auth" SIGINT
    gh auth login --git-protocol HTTPS --hostname github.com --web || true
    trap SIGINT
else
    echo seems like you\'re already logged in with \`gh\'
    echo to log in again, cancel the script with Ctrl+C, run the following command, and rerun the script:
    echo git config unset --all credential.https://github.com.helper
fi
echo

if [[ ! -d "$dir" ]]; then
    echo downloading...
    wget --quiet --show-progress "$url" -O "$file"
    rm --recursive --force "$dir"
    size=$(pigz --list "$file" | cut --delimiter ' ' --fields 2)
    unpigz --to-stdout "$file" | pv --interval 0.2 --name extract --size $size | tar --extract --file -
    rm "$file"
else
    echo seems like you already have WPILib installed \(found "$dir"\), skipping download
fi
echo

if [[ "$2027_format" = true ]]; then
    echo running the WPILib installer
    "$dir"/WPILibInstaller-CLI --yes --install-mode all
else
    echo installation instructions:
    echo 'press "Start", "Install for this User", "Download for this computer only"'
    echo when it becomes available, press the button labeled '"Next"'
    echo after installation has succeeded, press '"Finish"'
    "$dir"/WPILibInstaller
fi
echo

year="${ver%%\.*}"
alpha_suffix="${ver#*-}";
[[ "$alpha_suffix" = "$ver" ]] && alpha_suffix=
dir="$year${alpha_suffix:+_${alpha_suffix//-/}}"
echo all set. now launching the correct vscode so you can pin it to your taskbar
$(compat ~/.local/share/wpilib ~/wpilib)/"$dir"/vscode/*/code ~/FRC
