#!/bin/bash
set -e

function die {
    echo -e "$1"
    exit 1
}

[[ -z "$1" ]] && die "make sure you copied the command correctly. i need to know which WPILib version to install"

echo installing necessary packages
needed=(wget pv pigz tar git gh libicu-dev libnspr4 libnss3 clang-format)
missing_pkgs=($(comm -23 <(printf '%s\n' "${needed[@]}" | sort) <(dpkg-query --show --showformat '${Package}\n')))
[[ -z "$missing_pkgs" ]] || (sudo apt-get update && sudo apt-get install --yes "${missing_pkgs[@]}")

set +e
ver="$1"
dir="WPILib_Linux-x64-$ver"
file="$dir.tar.gz"
url="https://packages.wpilib.workers.dev/installer/v$ver/$file"
err="$(wget --spider $url 2>&1)"
[[ $? -ne 0 ]] && die "$(echo "seems like i can't download WPILib right now. try again later\nerror:\n")$err"
set -e

firstname="${USER%%_*}"
lastname="${USER##*_}"
while true; do
    echo name: "${firstname@u}" "${lastname@u}"
    email="${firstname@L}"_"${lastname@L}"@student.waylandps.org
    echo email: "$email"
    read -p "is this correct (Y/n)? " correct
    if [[ -z "$correct" || "${correct@L}" == y ]]; then
        git config --global user.name "${firstname@u} ${lastname@u}"
        git config --global user.email "$email"
        break
    fi

    read -p "first name: " firstname
    read -p "last name: " lastname
done

echo downloading robot code to ~/FRC
if [[ ! -d ~/FRC ]]; then
    git clone https://github.com/team5735/FRC ~/FRC
    cat > ~/FRC/.git/hooks/pre-push <<END
#!/bin/bash
set -e -o pipefail
# PS4=$'P \t$EPOCHREALTIME '

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
else
    cat <<END
~/FRC is already present, not overwriting
to redownload the repository, run the following in your terminal:
rm -rf ~/FRC; git clone https://github.com/team5735/FRC ~/FRC
END
fi

echo logging into GitHub. if you do not have an account you can make it now
echo to copy the one-time-code, select it and use Ctrl+Shift+C
echo unless you know better, you will want to authenticate git with your github credentials
trap "echo cancelled auth" SIGINT
gh auth login --git-protocol HTTPS --hostname github.com --web || true
trap SIGINT

echo downloading WPILib
wget --quiet --show-progress "$url" -O "$file"
rm --recursive --force $dir
size=$(pigz --list "$file" | cut --delimiter ' ' --fields 2)
unpigz --to-stdout "$file" | pv --interval 0.2 --name extract --size $size | tar --extract --file -
rm "$file"
echo running the WPILib installer
"$dir"/WPILibInstaller-CLI --yes --install-mode all

year="${ver%%\.*}"
alpha_suffix="${ver#*-}";
[[ "$alpha_suffix" = "$ver" ]] && alpha_suffix=
dir="$year${alpha_suffix:+_${alpha_suffix//-/}}"
~/.local/share/wpilib/"$dir"/vscode/*/code ~/FRC
