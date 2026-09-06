#!/bin/bash
set -ex

function die {
    echo -e "$1"
    exit 1
}

[[ -z "$1" ]] && die "make sure you copied the command correctly. i need to know which WPILib version to install"

echo installing necessary packages
needed=(wget pv pigz tar git gh)
missing_pkgs=($(comm -23 <(printf '%s\n' "${needed[@]}" | sort) <(dpkg-query --show --showformat '${Package}\n')))
[[ -z "$missing_pkgs" ]] || sudo apt-get install --yes "${missing_pkgs[@]}"

set +e
dir="WPILib_Linux-x64-$1"
file="$dir.tar.gz"
url="https://packages.wpilib.workers.dev/installer/v$1/$file"
err="$(wget --spider $url 2>&1)"
[[ $? -ne 0 ]] && die "$(echo "seems like i can't download WPILib right now. try again later\nerror:\n")$err"
set -e

while true; do
    read -p "first name: " firstname
    read -p "last name: " lastname
    echo name: "$firstname" "$lastname"
    email="${firstname@L}"_"${lastname@L}"@student.waylandps.org
    echo email: "$email"
    read -p "is this right (Y/n)? " correct
    ! [[ -z "$correct" || "${correct@L}" == y ]] && continue

    git config --global user.name "$firstname" "$lastname"
    git config --global user.email "$email"
    break
done

echo downloading robot code to ~/FRC
if [[ ! -d ~/FRC ]]; then
    git clone https://github.com/team5735/FRC ~/FRC
else
    cat <<END
~/FRC is already present, not overwriting
to redownload the repository, run the following in your terminal:
rm -rf ~/FRC; git clone https://github.com/team5735/FRC ~/FRC
END
fi

echo logging into GitHub. if you do not have an account you can make it now
echo to cancel the login, use Ctrl+C in the terminal
echo unless you know better, you will want to authenticate git with your github credentials
trap "echo cancelled auth" SIGINT
gh auth login --git-protocol HTTPS --hostname github.com --web || true
trap SIGINT

echo downloading WPILib
wget --quiet --show-progress "$url" -O $file
rm --recursive --force $dir
size=$(pigz --list $file | cut --delimiter ' ' --fields 2)
unpigz --to-stdout $file | pv --interval 0.2 --name extract --size $size | tar --extract --file -
echo running the WPILib installer
"$dir"/WPILibInstaller-CLI --yes --install-mode all
