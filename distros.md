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

```bash
git clone https://github.com/ticktechman/archlinux-img
cd archlinux-img
./build.sh
```




# oss

This vm use opensource linux and busybox 

```bash
 git clone --recursive https://github.com/ticktechman/oss-img
 cd oss-img
 ./build.sh
```

