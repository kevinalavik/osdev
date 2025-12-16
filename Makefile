.SUFFIXES:

QEMUFLAGS := -m 2G
override IMAGE_NAME := os

HOST_CC := cc
HOST_CFLAGS := -g -O2 -pipe
HOST_CPPFLAGS :=
HOST_LDFLAGS :=
HOST_LIBS :=

.PHONY: all
all: $(IMAGE_NAME).iso

.PHONY: run
run: edk2-ovmf $(IMAGE_NAME).iso
	@printf "\tRUN QEMU\n"
	@qemu-system-x86_64 \
		-M q35 \
		-drive if=pflash,unit=0,format=raw,file=edk2-ovmf/ovmf-code-x86_64.fd,readonly=on \
		-cdrom $(IMAGE_NAME).iso \
		-boot d \
		$(QEMUFLAGS)

edk2-ovmf:
	@printf "\tFETCH OVMF\n"
	@curl -L https://github.com/osdev0/edk2-ovmf-nightly/releases/latest/download/edk2-ovmf.tar.gz | gunzip | tar -xf -

limine/limine:
	@printf "\tCLONE LIMINE\n"
	@rm -rf limine
	@git clone https://codeberg.org/Limine/Limine.git limine --branch=v10.x-binary --depth=1
	@printf "\tMAKE LIMINE\n"
	@$(MAKE) -C limine \
		CC="$(HOST_CC)" \
		CFLAGS="$(HOST_CFLAGS)" \
		CPPFLAGS="$(HOST_CPPFLAGS)" \
		LDFLAGS="$(HOST_LDFLAGS)" \
		LIBS="$(HOST_LIBS)" >/dev/null

.PHONY: deps
deps:
	@printf "\tGEN MODULES\n"
	@python3 tools/modules.py modules.list

.PHONY: kernel
kernel: deps
	@printf "\tMAKE KERNEL\n"
	@$(MAKE) -C kernel

$(IMAGE_NAME).iso: limine/limine kernel
	@printf "\tBUILD ISO\n"
	@rm -rf iso_root
	@mkdir -p iso_root/boot
	@cp -v kernel/bin/kernel iso_root/boot/ >/dev/null
	@mkdir -p iso_root/boot/limine
	@cp -v limine.conf limine/limine-bios.sys limine/limine-bios-cd.bin limine/limine-uefi-cd.bin iso_root/boot/limine/ >/dev/null
	@mkdir -p iso_root/EFI/BOOT
	@cp -v limine/BOOTX64.EFI iso_root/EFI/BOOT/ >/dev/null
	@cp -v limine/BOOTIA32.EFI iso_root/EFI/BOOT/ >/dev/null
	@xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus \
		-apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		iso_root -o $(IMAGE_NAME).iso >/dev/null
	@./limine/limine bios-install $(IMAGE_NAME).iso >/dev/null
	@rm -rf iso_root

$(IMAGE_NAME).hdd: limine/limine kernel
	@printf "\tBUILD HDD IMAGE\n"
	@rm -f $(IMAGE_NAME).hdd
	@dd if=/dev/zero bs=1M count=0 seek=64 of=$(IMAGE_NAME).hdd >/dev/null 2>&1
	@PATH=$$PATH:/usr/sbin:/sbin sgdisk $(IMAGE_NAME).hdd -n 1:2048 -t 1:ef00 -m 1 >/dev/null
	@./limine/limine bios-install $(IMAGE_NAME).hdd >/dev/null
	@mformat -i $(IMAGE_NAME).hdd@@1M >/dev/null
	@mmd -i $(IMAGE_NAME).hdd@@1M ::/EFI ::/EFI/BOOT ::/boot ::/boot/limine >/dev/null
	@mcopy -i $(IMAGE_NAME).hdd@@1M kernel/bin/kernel ::/boot >/dev/null
	@mcopy -i $(IMAGE_NAME).hdd@@1M limine.conf limine/limine-bios.sys ::/boot/limine >/dev/null
	@mcopy -i $(IMAGE_NAME).hdd@@1M limine/BOOTX64.EFI ::/EFI/BOOT >/dev/null
	@mcopy -i $(IMAGE_NAME).hdd@@1M limine/BOOTIA32.EFI ::/EFI/BOOT >/dev/null

.PHONY: clean
clean:
	@printf "\tCLEAN\n"
	@$(MAKE) -C kernel clean >/dev/null
	@rm -rf iso_root $(IMAGE_NAME).iso $(IMAGE_NAME).hdd

.PHONY: distclean
distclean: clean
	@printf "\tDISTCLEAN"
	@$(MAKE) -C kernel distclean >/dev/null
	@rm -rf kernel-deps limine edk2-ovmf
