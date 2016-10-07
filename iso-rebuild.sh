#!/bin/bash

# http://forum.runtu.org/index.php/topic,611.0.html

# скрипт для пересборки runtu (проверено на 10.04), должен работать и в ubuntu
# запускать от рута (sudo)
# параметры:
#    $1 - исходный образ системы

# функция проверяет,
# установлен ли пакет в системе
#============================
check_package ()
{
if [ -n "`dpkg -l $1 | grep ^ii`" ]
then
  echo "Checking $1... OK"
else
  echo "Checking $1... Not found!"
  echo "use: apt-get install $1"
  exit 1
fi
}
#============================

# проверка необходимых для работы пакетов
check_package rsync
check_package squashfs-tools
check_package syslinux-utils
check_package genisoimage

# рабочие директории
sourcedir=ubuntu-source    # распакованный squashfs
builddir=ubuntu-rebuild    # распакованный образ системы

# проверка точки монтирования /mnt/loop
if [ -d "/mnt/loop" ]
then
 if [ -n "`ls /mnt/loop/`" ]
  then printf "Something at /mnt/loop/. Continue anyway? [y/N] "
  read answer
  if [ "$answer"  != "y"  ]
   then exit 1
  fi
 fi
else mkdir /mnt/loop
fi

# монтирование и извлечение исходного образа
echo
echo "Unpack image..."
mount -o loop $1 /mnt/loop
mkdir $builddir
rsync -ax /mnt/loop/. $builddir
umount /mnt/loop

# монтирование и извлечение squashfs
mount $builddir/casper/filesystem.squashfs /mnt/loop -t squashfs -o loop
mkdir $sourcedir
rsync -av /mnt/loop/. $sourcedir
umount /mnt/loop

# копирование resolv.conf и чрут
cp /etc/resolv.conf $sourcedir/etc/

# обновление пакетов
echo
printf "Sync packages with apt-get? [y/N] " 
read answer
if [ "$answer"  = "y"  ]
 then
  echo "Sync package lists..."
  chroot $sourcedir apt-get update
  chroot $sourcedir apt-get -y upgrade
fi
echo
echo "Entering chroot..."
echo "Customize your system. Type 'exit' to leave chroot and make image."
chroot $sourcedir

# удаление ненужных файлов
echo
echo "Cleaning..."
rm $sourcedir/var/cache/apt/archives/*.deb
rm $sourcedir/etc/resolv.conf
chroot $sourcedir ln -s /run/resolvconf/resolv.conf /etc/resolv.conf

echo
echo "Pack image..."
# обновление filesystem.manifest
chroot $sourcedir dpkg-query -W --showformat='${Package} ${Version}\n' > $builddir/casper/filesystem.manifest

# обновление filesystem.manifest-desktop
cat > /tmp/sedscript <<END
/casper/d
/libdebian-installer4/d
/os-prober/d
/ubiquity/d
/ubuntu-live/d
/user-setup/d
END
sed -f /tmp/sedscript <  $builddir/casper/filesystem.manifest > $builddir/casper/filesystem.manifest-desktop
rm /tmp/sedscript

# обновление filesystem.size
printf $(du -sx --block-size=1 $sourcedir | cut -f1) > $builddir/casper/filesystem.size

# создание  filesystem.squashfs
mksquashfs $sourcedir $builddir/casper/filesystem.squashfs -comp xz -noappend

# создание  md5sum.txt
cd $builddir && find . -type f -print0 | xargs -0 md5sum > md5sum.txt
cd ..

# создание  iso-образа системы
resultISO=`date +%Y%m%d-%H%M%S`.iso
mkisofs -r -V "ubuntu-remix-`date +%Y%m%d `" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $resultISO $builddir
isohybrid $resultISO

# удаление временных файлов
echo
printf "Done. Remove unpacked files? [Y/n] " 
read answer
if [ "$answer"  = "n"  ]
 then exit 0
fi
rm -R $sourcedir $builddir
exit 0

