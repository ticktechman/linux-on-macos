# Notice

- kernel: uncompressed raw image(recommended) or compressed raw image(with CONFIG_KERNEL_GZIP=y) -- Image / Image.gz(from directory: boot/arch/arm64/)
- initrd: cpio / cpio + gzip
- rootfs: raw disk image(with or without partitions)



# ubuntu

This vm use ubuntu cloud image and a generated seed.iso for cloud-init.

```bash
git clone https://github.com/ticktechman/ubuntu-img
cd ubuntu-img
./build.sh
./gen-seed.sh
```



# archlinux

This vm use http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz for all stuff

- kernel: boot/Image 
- initrd: boot/initramfs-linux-fallback.img
- rootfs: ArchLinuxARM-aarch64-latest.tar.gz


# oss

This vm use opensource linux and busybox 

```bash
 git clone --recursive https://github.com/ticktechman/oss-img
 cd oss-img
 ./build.sh
```

