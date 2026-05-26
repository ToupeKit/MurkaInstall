#!/bin/bash

# 1. Работа с дисками
lsblk
echo "------------------------------------------------------"
read -p "Введите имя диска (например, sda или nvme0n1): " DISK
read -p "Введите размер EFI раздела в Мб (например, 512): " EFI_SIZE

# Разметка (стираем всё!)
parted /dev/$DISK -- mklabel gpt
parted /dev/$DISK -- mkpart ESP fat32 1MiB ${EFI_SIZE}MiB
parted /dev/$DISK -- set 1 esp on
parted /dev/$DISK -- mkpart primary ext4 ${EFI_SIZE}MiB 100%

# Определяем имена разделов (учитываем nvme)
if [[ $DISK == nvme* ]]; then
    PART_EFI="/dev/${DISK}p1"
    PART_ROOT="/dev/${DISK}p2"
else
    PART_EFI="/dev/${DISK}1"
    PART_ROOT="/dev/${DISK}2"
fi

# Форматирование
mkfs.fat -F 32 $PART_EFI
mkfs.ext4 $PART_ROOT

# Монтирование
mount $PART_ROOT /mnt
mount --mkdir $PART_EFI /mnt/boot/efi

# 2. Настройка pacman.conf (Multilib)
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf

# 3. Базовая установка
pacstrap /mnt base linux linux-firmware nano sudo

# Генерация fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 4. Выбор окружения
echo "Выберите окружение:"
echo "1) GNOME (как Ubuntu)"
echo "2) Hyprland (Тайлинг)"
echo "3) KDE Plasma (как Windows)"
read -p "Ваш выбор: " DE_CHOICE

case $DE_CHOICE in
    1) DE_PKGS="gnome gnome-extra" ;;
    2) DE_PKGS="hyprland kitty waybar wofi mako swaybg xdg-desktop-portal-hyprland qt5-wayland qt6-wayland" ;;
    3) DE_PKGS="plasma-desktop sddm konsole dolphin" ;;
esac

# 5. Создание пользователя
read -p "Введите имя пользователя: " USERNAME
read -s -p "Введите пароль пользователя: " USERPASS
echo ""

# Входим в chroot для финальной настройки
arch-chroot /mnt /bin/bash <<EOF
# Часовой пояс и время
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc

# Локализация
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf
echo "TPArch" > /etc/hostname

# Пользователь и Sudo
echo "root:root_password_here" | chpasswd # Рекомендую сменить
useradd -m -G wheel $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Репозитории внутри chroot
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf

# Установка софта
pacman -Sy --noconfirm grub efibootmgr networkmanager mesa lib32-mesa intel-media-driver intel-ucode pipewire pipewire-pulse pipewire-alsa wireplumber ttf-font-awesome ttf-dejavu noto-fonts-cjk $DE_PKGS

# Загрузчик
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

# Сервисы
systemctl enable NetworkManager
if [ "$DE_CHOICE" = "3" ] || [ "$DE_CHOICE" = "1" ]; then
    systemctl enable sddm || systemctl enable gdm
fi

EOF

# Завершение
umount -R /mnt
echo "Установка завершена! Перезагрузитесь."