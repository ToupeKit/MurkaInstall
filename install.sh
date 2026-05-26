#!/bin/bash

# Устанавливаем шрифт в текущей сессии установщика
setfont cyr-sun16

# 1. Работа с диском
lsblk
echo "------------------------------------------------------"
read -p "Выберите диск (например, sda): " DISK
read -p "Мегабайты для EFI (например, 512): " EFI_SIZE

parted /dev/$DISK -- mklabel gpt
parted /dev/$DISK -- mkpart ESP fat32 1MiB ${EFI_SIZE}MiB
parted /dev/$DISK -- set 1 esp on
parted /dev/$DISK -- mkpart primary ext4 ${EFI_SIZE}MiB 100%

[[ $DISK == nvme* ]] && P="p" || P=""
PART_EFI="/dev/${DISK}${P}1"
PART_ROOT="/dev/${DISK}${P}2"

mkfs.fat -F 32 $PART_EFI
mkfs.ext4 $PART_ROOT
mount $PART_ROOT /mnt
mount --mkdir $PART_EFI /mnt/boot/efi

# 2. Pacman Multilib
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf

# 3. База (обязательно terminus-font)
pacstrap /mnt base linux linux-firmware nano sudo terminus-font

genfstab -U /mnt >> /mnt/etc/fstab

# 4. Выбор DE
echo "1) GNOME | 2) Hyprland | 3) KDE"
read -p "Выбор: " DE_CHOICE
case $DE_CHOICE in
    1) DE_PKGS="gnome gnome-extra" ;;
    2) DE_PKGS="hyprland kitty waybar wofi mako swaybg xdg-desktop-portal-hyprland qt5-wayland qt6-wayland" ;;
    3) DE_PKGS="plasma-desktop sddm konsole dolphin" ;;
esac

# 5. Юзер
read -p "Имя пользователя: " USERNAME
read -s -p "Пароль: " USERPASS
echo ""

# Входим в chroot
arch-chroot /mnt /bin/bash <<EOF
# Часовой пояс
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc

# --- НАСТРОЙКА ЛОКАЛИ (Способ через прямую запись) ---
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen

# Генерируем локали
locale-gen

# Устанавливаем системный язык
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf

# Настраиваем шрифт для консоли (чтобы не было квадратов при загрузке)
echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf

echo "TPArch" > /etc/hostname

# Юзер и права
useradd -m -G wheel $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd
# Разрешаем wheel использовать sudo без пароля или с паролем (раскомментируем строку)
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# Повторяем multilib внутри
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf

# Софт
pacman -Sy --noconfirm grub efibootmgr networkmanager mesa lib32-mesa intel-media-driver intel-ucode pipewire pipewire-pulse pipewire-alsa wireplumber ttf-font-awesome ttf-dejavu noto-fonts-cjk $DE_PKGS

# Загрузчик
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
[[ "$DE_CHOICE" == "1" ]] && systemctl enable gdm
[[ "$DE_CHOICE" == "3" ]] && systemctl enable sddm
EOF

umount -R /mnt
echo "Готово! Теперь локали сгенерированы правильно."
