echo "Debian installation script"
echo "Works only on UEFI systems, and create only two partitions: EFI and root."

while true; do
    echo "What Debian version do you want to install?"
    echo "1. Stable"
    echo "2. Testing"
    echo "3. Sid"
    read -p "Choose your preferred Debian version: " WERSJA
    case $WERSJA in
        1)
            WERSJA="stable"
            echo "You selected Debian Stable."
            break
            ;;
        2)
            WERSJA="testing"
            echo "You selected Debian Testing."
            break
            ;;
        3)
            WERSJA="sid"
            echo "You selected Debian Sid."
            break
            ;;
        *)
            echo "Invalid choice. Please select 1, 2, or 3."
            ;;
    esac
done

while true; do
    DYSKI=($(lsblk -d -n -o NAME))

    echo "Enter the disk where you want to install Debian:"
    for i in "${!DYSKI[@]}"; do
        echo "$((i+1)). ${DYSKI[$i]}"
    done

    read -p "Enter the number of your choice: " WYBOR

    if [[ "$WYBOR" =~ ^[0-9]+$ ]] && [ "$WYBOR" -ge 1 ] && [ "$WYBOR" -le "${#DYSKI[@]}" ]; then
        DYSK="/dev/${DYSKI[$((WYBOR-1))]}"
        echo "You selected disk: $DYSK."
        break
    else
        echo "Invalid choice. Please select a valid number."
    fi
done

while true; do
    echo "Which filesystem do you want to use?"
    echo "1. ext4"
    echo "2. btrfs TODO"
    echo "3. xfs   TODO"
    echo "4. zfs   TODO"
    read -p "Enter the number of your choice: " FS

    case $FS in
        1)
            FS=ext4
            break
            ;;
        2)
            echo "Btrfs is not supported by this script yet."
            ;;
        3)
            echo "XFS is not supported by this script yet."
            ;;
        4)
            echo "ZFS is not supported by this script yet."
            ;;
        *)
            echo "Invalid choice. Please select a valid number."
            ;;
    esac
done

while true; do
    read -p "WARNING: This will erase all data on $DYSK. Continue? (yes/no): " confirm
    case $confirm in
        yes)
            break
            ;;
        no)
            echo "Operation cancelled."
            exit 1
            ;;
        *)
            echo "Invalid choice. Please select 'yes' or 'no'."
            ;;
    esac
done

echo "Creating partitions on $DYSK..."

parted "$DYSK" --script mklabel gpt \
    mkpart boot fat32 1MiB 1001MiB \
    set 1 esp on \
    mkpart primary $FS 1001MiB 100%

echo "Partitions created:"
lsblk "$DYSK"

echo "Finished partitioning $DYSK."

echo "Formatting partitions..."
mkfs.vfat "${DYSK}1"
mkfs."$FS" "${DYSK}2"

mount "${DYSK}2" /mnt
mkdir -p /mnt/boot/efi
mount "${DYSK}1" /mnt/boot/efi

apt-get update && apt-get upgrade -y
apt-get install -y debootstrap

debootstrap $WERSJA /mnt

cat <<EOF > /mnt/etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware

deb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF

for dir in sys dev proc; do
    mount --rbind /$dir /mnt/$dir && mount --make-rslave /mnt/$dir
done

chroot /mnt /bin/bash -c "apt-get update && apt-get upgrade -y && apt-get install -y linux-image-amd64 grub-efi-amd64 efibootmgr"
chroot /mnt /bin/bash -c "grub-install /dev/${DYSK}1 && update-grub"

# Setting up fstab
EFI_UUID=$(blkid -s UUID -o value "${DYSK}1")
ROOT_UUID=$(blkid -s UUID -o value "${DYSK}2")

cat <<EOF > /mnt/etc/fstab
UUID=$ROOT_UUID / $FS defaults 0 1
UUID=$EFI_UUID /boot/efi vfat defaults 0 1
EOF

# Network configuration
cat <<EOF > /mnt/etc/network/interfaces
auto lo
iface lo inet loopback

auto enp0s1
iface enp0s1 inet dhcp
EOF

chroot /mnt /bin/bash -c "apt-get install -y dhcpcd && systemctl enable dhcpcd" 


echo "Installation finished. Change your root password and reboot."
echo "Root password:"
chroot /mnt /bin/bash -c "passwd"