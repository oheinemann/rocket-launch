$user = "oliver.heinemann"
$pass = "Maren2019!"
$distrolist = (
    [PSCustomObject]@{
        'Name' = 'Debian'
        'URI' = 'https://aka.ms/wsl-debian-gnulinux'
        'AppxName' = 'TheDebianProject.DebianGNULinux'
        'winpe' = 'debian.exe'
        'installed' = $false
    }
)

$distro = $distrolist[0]

$processOptions = @{
    FilePath = $Distro.winpe
    ArgumentList = ' config --default-user root'
}

Start-Process $processOptions
wsl.exe -d $Distro.Name -u root useradd --force-badname --create-home --user-group --groups  adm,dialout,cdrom,floppy,sudo,audio,dip,video,plugdev,netdev --password "$pass" $user

