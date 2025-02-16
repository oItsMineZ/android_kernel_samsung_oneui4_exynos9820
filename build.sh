#!/bin/bash

export MODEL=$1
export BUILD_CROSS_COMPILE=$(pwd)/toolchain/aarch64-linux-android-4.9/bin/aarch64-linux-androidkernel-
export BUILD_JOB_NUMBER=`grep -c ^processor /proc/cpuinfo`
RDIR=$(pwd)

case $MODEL in
beyond2lte)
    SOC=9820
    BOARD=SRPRI17C014KU
;;
beyond1lte)
    SOC=9820
    BOARD=SRPRI28B014KU
;;
beyond0lte)
    SOC=9820
    BOARD=SRPRI28A014KU
;;
beyondx)
    SOC=9820
    BOARD=SRPSC04B011KU
;;
d1)
    SOC=9825
    BOARD=SRPSD26B007KU
;;
d1x)
    SOC=9825
    BOARD=SRPSD23A002KU
;;
d2s)
    SOC=9825
    BOARD=SRPSC14B007KU
;;
d2x)
    SOC=9825
    BOARD=SRPSC14C007KU
;;
*)
    echo "Unknown device: $MODEL setting to d2s"
    MODEL=d2s
    SOC=9825
    BOARD=SRPSC14B007KU
esac
KERNEL_DEFCONFIG=oitsminez-"$MODEL"_defconfig

FUNC_BUILD_KERNEL()
{
    echo " Starting a kernel build using "$KERNEL_DEFCONFIG ""

    if [[ "$SOC" == "9825" ]]; then
        NOTE10=exynos9825.config
    fi

    make -j$BUILD_JOB_NUMBER ARCH=arm64 \
        CROSS_COMPILE=$BUILD_CROSS_COMPILE \
        $KERNEL_DEFCONFIG oitsminez.config ksu_next.config $NOTE10 || exit -1

    make -j$BUILD_JOB_NUMBER ARCH=arm64 \
        CROSS_COMPILE=$BUILD_CROSS_COMPILE || exit -1

    $RDIR/toolchain/mkdtimg cfg_create build/dtb_$SOC.img \
        $RDIR/toolchain/configs/exynos$SOC.cfg \
        -d $RDIR/arch/arm64/boot/dts/exynos

    echo " Finished kernel build"
}

FUNC_BUILD_DTBO()
{
    $RDIR/toolchain/mkdtimg cfg_create build/dtbo_$MODEL.img \
        $RDIR/toolchain/configs/$MODEL.cfg \
        -d $RDIR/arch/arm64/boot/dts/samsung
}

FUNC_BUILD_RAMDISK()
{
    rm -f $RDIR/ramdisk/split_img/boot.img-kernel
    cp $RDIR/arch/arm64/boot/Image $RDIR/ramdisk/split_img/boot.img-kernel
    echo $BOARD > ramdisk/split_img/boot.img-board
    # This is kinda ugly hack, we could as well touch .placeholder to all of those
    mkdir -p $RDIR/ramdisk/ramdisk/debug_ramdisk
    mkdir -p $RDIR/ramdisk/ramdisk/dev
    mkdir -p $RDIR/ramdisk/ramdisk/mnt
    mkdir -p $RDIR/ramdisk/ramdisk/proc
    mkdir -p $RDIR/ramdisk/ramdisk/sys

    rm -rf $RDIR/ramdisk/ramdisk/fstab.exynos9820
    rm -rf $RDIR/ramdisk/ramdisk/fstab.exynos9825

    cp $RDIR/ramdisk/fstab.exynos$SOC $RDIR/ramdisk/ramdisk/

    cd $RDIR/ramdisk/
    ./repackimg.sh --nosudo
}

FUNC_BUILD_ZIP()
{
    cd $RDIR/build
    rm -rf $MODEL-boot-ramdisk.img
    mv $RDIR/ramdisk/image-new.img $RDIR/build/$MODEL-boot-ramdisk.img

    # Make recovery flashable package
    rm -rf $RDIR/build/zip
    mkdir -p $RDIR/build/zip
    cp $RDIR/build/$MODEL-boot-ramdisk.img $RDIR/build/zip/boot.img
    cp $RDIR/build/dtb_$SOC.img $RDIR/build/zip/dtb.img
    cp $RDIR/build/dtbo_$MODEL.img $RDIR/build/zip/dtbo.img
    mkdir -p $RDIR/build/zip/META-INF/com/google/android/
    cp $RDIR/toolchain/updater-script $RDIR/build/zip/META-INF/com/google/android/
    cp $RDIR/toolchain/update-binary $RDIR/build/zip/META-INF/com/google/android/
    cd $RDIR/build/zip
    zip -r ../kernel_$MODEL.zip .
    rm -rf $RDIR/build/zip
    cd $RDIR/build
}

# MAIN FUNCTION
rm -rf ./build.log
(
	START_TIME=`date +%s`

	FUNC_BUILD_KERNEL
	FUNC_BUILD_DTBO
	FUNC_BUILD_RAMDISK
	FUNC_BUILD_ZIP

	END_TIME=`date +%s`

	let "ELAPSED_TIME=$END_TIME-$START_TIME"
	echo "Total compile time was $ELAPSED_TIME seconds"

) 2>&1	| tee -a ./build.log
