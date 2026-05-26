#!/bin/bash

# Функция для вывода красного текста при ошибке
error_exit() {
    echo -e "\n\e[1;31m[ОШИБКА] $1\e[0m"
    exit 1
}

# --- 1. Активация русского языка в инсталляторе ---
echo "ru_RU.UTF-8 UTF-8" > /etc/locale.gen
locale-gen || error_exit "Не удалось сгенерировать локаль на ISO"
export LANG=ru_RU.UTF-8
setfont cyr-sun16
echo "Русский язык в установщике включен!"

# --- 2. Работа с дисками ---
lsblk
echo "------------------------------------------------------"
read -p "Выберите диск (например, sda): " DISK

if [ ! -b "/dev/$DISK" ]; then
    error_exit "Диск /dev/$DISK не существует!"
fi

read -p "Размер EFI (в Мб, например 512): " EFI_SIZE
# Проверка, что введено число
if [[ ! "$EFI_SIZE" =~ ^[0-9]+$ ]]; then
    error_exit "Размер EFI должен быть числом!"
fi

echo "Разметка диска..."
parted /dev/$DISK -- mklabel gpt || error_exit "Не удалось создать таблицу GPT"
parted /dev/$DISK -- mkpart ESP fat32 1MiB ${EFI_SIZE}MiB || error_exit "Не удалось создать EFI раздел"
parted /dev/$DISK -- set 1 esp on
parted /dev/$DISK -- mkpart primary ext4 ${EFI_SIZE}MiB 100% || error_exit "Не удалось создать корневой раздел"

[[ $DISK == nvme* ]] && P="p" || P=""
PART_EFI="/dev/${DISK}${P}1"
PART_ROOT="/dev/${DISK}${P}2"

echo "Форматирование..."
mkfs.fat -F 32 $PART_EFI || error_exit "Ошибка форматирования EFI"
mkfs.ext4 -F $PART_ROOT || error_exit "Ошибка форматирования Root"

echo "Монтирование..."
mount $PART_ROOT /mnt || error_exit "Не удалось смонтировать /mnt"
mount --mkdir $PART_EFI /mnt/boot/efi || error_exit "Не удалось смонтировать /mnt/boot/efi"

# --- 3. Настройка репозиториев ---
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf

# --- 4. Установка базы ---
echo "Запуск pacstrap... Не прерывайте процесс!"
pacstrap /mnt base linux linux-firmware nano sudo terminus-font || error_exit "pacstrap завершился с ошибкой! Проверьте интернет или зеркала."

genfstab -U /mnt >> /mnt/etc/fstab

# --- 5. Выбор окружения (с жестким циклом проверки) ---
while true; do
    echo "Выберите рабочий стол:"
    echo "1) GNOME"
    echo "2) Hyprland"
    echo "3) KDE Plasma"
    read -p "Ваш выбор (1-3): " DE_CHOICE
    case $DE_CHOICE in
        1) DE_PKGS="gnome gnome-extra"; break ;;
        2) DE_PKGS="hyprland kitty waybar wofi mako swaybg xdg-desktop-portal-hyprland qt5-wayland qt6-wayland"; break ;;
        3) DE_PKGS="plasma-desktop sddm konsole dolphin"; break ;;
        *) echo -e "\e[1;33mНеверный выбор! Введите цифру от 1 до 3.\e[0m" ;;
    esac
done

# --- 6. Создание пользователя ---
while true; do
    read -p "Имя пользователя: " USERNAME
    if [[ -z "$USERNAME" ]]; then
        echo "Имя пользователя не может быть пустым!"
    else
        break
    fi
done

read -s -p "Пароль пользователя: " USERPASS
echo ""

# --- 7. Настройка системы внутри chroot ---
# Проверяем, что в /mnt вообще есть bash перед запуском chroot
if [ ! -f "/mnt/bin/bash" ]; then
    error_exit "Критическая ошибка: Базовая система не была установлена в /mnt!"
fi

echo "Переходим в chroot..."
arch-chroot /mnt /bin/bash <<EOF
set -e

ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc

echo "ru_RU.UTF-8 UTF-8" > /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf

echo "KEYMAP=ru" > /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf

echo "TPArch" > /etc/hostname

useradd -m -G wheel $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf

pacman -Sy --noconfirm grub efibootmgr networkmanager mesa lib32-mesa intel-media-driver intel-ucode pipewire pipewire-pulse pipewire-alsa wireplumber ttf-font-awesome ttf-dejavu noto-fonts-cjk $DE_PKGS

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
if [[ "$DE_CHOICE" == "1" ]]; then systemctl enable gdm; fi
if [[ "$DE_CHOICE" == "3" ]]; then systemctl enable sddm; fi
EOF

# Конец
umount -R /mnt
echo "------------------------------------------------------"
echo -e "\e[1;32mУстановка УСПЕШНО завершена! Перезагружайтесь.\e[0m"