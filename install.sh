#!/bin/bash

# --- 1. Активация русского языка прямо в инсталляторе ---
echo "ru_RU.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
export LANG=ru_RU.UTF-8
setfont cyr-sun16
echo "Русский язык в установщике включен!"

# --- 2. Работа с дисками ---
lsblk
echo "------------------------------------------------------"
read -p "Выберите диск (например, sda): " DISK
read -p "Размер EFI (в Мб, например 512): " EFI_SIZE

# Разметка (GPT)
parted /dev/$DISK -- mklabel gpt
parted /dev/$DISK -- mkpart ESP fat32 1MiB ${EFI_SIZE}MiB
parted /dev/$DISK -- set 1 esp on
parted /dev/$DISK -- mkpart primary ext4 ${EFI_SIZE}MiB 100%

# Проверка на NVMe (p1/p2) или SATA (1/2)
[[ $DISK == nvme* ]] && P="p" || P=""
PART_EFI="/dev/${DISK}${P}1"
PART_ROOT="/dev/${DISK}${P}2"

# Форматирование
mkfs.fat -F 32 $PART_EFI
mkfs.ext4 $PART_ROOT

# Монтирование
mount $PART_ROOT /mnt
mount --mkdir $PART_EFI /mnt/boot/efi

# --- 3. Настройка репозиториев ---
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf

# --- 4. Установка базы (включаем terminus-font для консоли) ---
pacstrap /mnt base linux linux-firmware nano sudo terminus-font

genfstab -U /mnt >> /mnt/etc/fstab

# --- 5. Выбор окружения ---
echo "Выберите рабочий стол:"
echo "1) GNOME"
echo "2) Hyprland"
echo "3) KDE Plasma"
read -p "Ваш выбор: " DE_CHOICE

case $DE_CHOICE in
    1) DE_PKGS="gnome gnome-extra" ;;
    2) DE_PKGS="hyprland kitty waybar wofi mako swaybg xdg-desktop-portal-hyprland qt5-wayland qt6-wayland" ;;
    3) DE_PKGS="plasma-desktop sddm konsole dolphin" ;;
esac

# --- 6. Создание пользователя ---
read -p "Имя пользователя: " USERNAME
read -s -p "Пароль пользователя: " USERPASS
echo ""

# --- 7. Настройка системы внутри chroot ---
arch-chroot /mnt /bin/bash <<EOF
# Часовой пояс
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc

# Локализация внутри системы
echo "ru_RU.UTF-8 UTF-8" > /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf

# Чтобы в консоли (TTY) всегда был русский
echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf

echo "TPArch" > /etc/hostname

# Настройка пользователя
useradd -m -G wheel $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd
# Даем права sudo (разрешаем группе wheel)
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Включаем multilib в установленной системе
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf

# Установка софта
pacman -Sy --noconfirm grub efibootmgr networkmanager mesa lib32-mesa intel-media-driver intel-ucode pipewire pipewire-pulse pipewire-alsa wireplumber ttf-font-awesome ttf-dejavu noto-fonts-cjk $DE_PKGS

# Установка загрузчика
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

# Включение сервисов
systemctl enable NetworkManager
if [[ "$DE_CHOICE" == "1" ]]; then systemctl enable gdm; fi
if [[ "$DE_CHOICE" == "3" ]]; then systemctl enable sddm; fi

EOF

# Конец
umount -R /mnt
echo "------------------------------------------------------"
echo "Установка завершена! Можно перезагружаться (reboot)."
