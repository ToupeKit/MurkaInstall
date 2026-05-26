#!/bin/bash

# --- 0. Настройка шрифтов для нормального русского в консоли ---
setfont cyr-sun16
echo "Поддержка русского языка в консоли активирована."

# 1. Работа с дисками
lsblk
echo "------------------------------------------------------"
read -p "Введите имя диска (например, sda): " DISK
read -p "Размер EFI раздела в Мб (например, 512): " EFI_SIZE

# Разметка
parted /dev/$DISK -- mklabel gpt
parted /dev/$DISK -- mkpart ESP fat32 1MiB ${EFI_SIZE}MiB
parted /dev/$DISK -- set 1 esp on
parted /dev/$DISK -- mkpart primary ext4 ${EFI_SIZE}MiB 100%

# Определение разделов
[[ $DISK == nvme* ]] && P="p" || P=""
PART_EFI="/dev/${DISK}${P}1"
PART_ROOT="/dev/${DISK}${P}2"

# Форматирование и монтаж
mkfs.fat -F 32 $PART_EFI
mkfs.ext4 $PART_ROOT
mount $PART_ROOT /mnt
mount --mkdir $PART_EFI /mnt/boot/efi

# 2. Подготовка pacman.conf
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf

# 3. Базовая установка (добавляем terminus-font для кириллицы)
pacstrap /mnt base linux linux-firmware nano sudo terminus-font

genfstab -U /mnt >> /mnt/etc/fstab

# 4. Выбор окружения
echo "Выберите окружение:"
echo "1) GNOME (Ubuntu-style)"
echo "2) Hyprland (Tiling)"
echo "3) KDE Plasma (Windows-style)"
read -p "Выбор: " DE_CHOICE

case $DE_CHOICE in
    1) DE_PKGS="gnome gnome-extra" ;;
    2) DE_PKGS="hyprland kitty waybar wofi mako swaybg xdg-desktop-portal-hyprland qt5-wayland qt6-wayland" ;;
    3) DE_PKGS="plasma-desktop sddm konsole dolphin" ;;
esac

# 5. Пользователь
read -p "Имя пользователя: " USERNAME
read -s -p "Пароль: " USERPASS
echo ""

# Входим в chroot
arch-chroot /mnt /bin/bash <<EOF
# Время и локаль
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc

# Генерируем нормальную русскую локаль
sed -i 's/#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
# Настройка шрифта для консоли, чтобы не было латиницы/квадратов
echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf

echo "TPArch" > /etc/hostname

# Пользователь
useradd -m -G wheel $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Multilib внутри системы
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf

# Установка софта
pacman -Sy --noconfirm grub efibootmgr networkmanager mesa lib32-mesa intel-media-driver intel-ucode pipewire pipewire-pulse pipewire-alsa wireplumber ttf-font-awesome ttf-dejavu noto-fonts-cjk $DE_PKGS

# Загрузчик
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
[[ "$DE_CHOICE" == "1" ]] && systemctl enable gdm
[[ "$DE_CHOICE" == "3" ]] && systemctl enable sddm

EOF

umount -R /mnt
echo "Готово! Теперь русский будет отображаться корректно."
